defmodule Membrane.RTMP.Source do
  @moduledoc """
  Membrane Element for receiving RTMP streams. Acts as a RTMP Server.
  This implementation is limited to only AAC and H264 streams.
  """
  use Membrane.Source

  require Membrane.Logger

  alias Membrane.{AVC, Buffer, Time, Logger}
  alias Membrane.RTMP.{Interceptor, Handshake, Header, Message, Messages, Responses}
  alias Membrane.RTMP.Messages.Serializer

  def_output_pad :audio,
    availability: :always,
    caps: Membrane.AAC.RemoteStream,
    mode: :pull

  def_output_pad :video,
    availability: :always,
    caps: Membrane.H264.RemoteStream,
    mode: :pull

  def_options port: [
                spec: non_neg_integer(),
                description: """
                Port on which the FFmpeg instance will be created
                """
              ],
              timeout: [
                spec: Time.t() | :infinity,
                default: :infinity,
                description: """
                Time the server will wait for a connection from the client

                Duration given must be a multiply of one second or atom `:infinity`.
                """
              ]

  @impl true
  def handle_init(%__MODULE__{} = opts) do
    {:ok,
     Map.from_struct(opts)
     |> Map.merge(%{
       stale_frame: nil,
       interceptor: Interceptor.init(Handshake.init_server()),
       client_pid: nil,
       client_socket: nil,
       # epoch required for performing a handshake with the pipeline
       epoch: 0
     })}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    target_pid = self()

    Logger.debug("Establishing connection on port: #{state.port}")

    pid =
      spawn_link(fn ->
        {:ok, socket} =
          :gen_tcp.listen(state.port, [:binary, packet: :raw, active: :once, reuseaddr: true])

        {:ok, client} = :gen_tcp.accept(socket)

        Logger.debug("Established connection with client, socket: #{inspect(client)}")

        receive_loop(client, target_pid)
      end)

    Logger.debug("Receiver started, pid: #{inspect(pid)}")

    # actions = [
    #   caps:
    #     {:video,
    #      %Membrane.H264.RemoteStream{
    #        decoder_configuration_record:
    #          <<1::8, 0::8, 0::8, 0::8, 0b111111::6, 0::2, 0b111::3, 0::13>>,
    #        stream_format: :avc1
    #      }},
    #   # caps: {:audio, %Membrane.AAC.RemoteStream{audio_specific_config: <<1::5, 0::4, 0::4, 0::1>>}},
    #   buffer: {:video, %Membrane.Buffer{payload: nil}}
    #   # buffer: {:audio, %Membrane.Buffer{payload: nil}}
    # ]

    {:ok, %{state | client_pid: pid}}
  end

  defp receive_loop(socket, target) do
    receive do
      :need_more_data ->
        :inet.setopts(socket, active: :once)
        Logger.debug("Receiver requesting more data")

      {:tcp, _port, packet} ->
        Logger.debug("Receiver got packet: #{inspect(packet)}")
        send(target, {:tcp, socket, packet})

      message ->
        Logger.debug("Receiver got unknown message: #{inspect(message)}")
        :noop
    end

    receive_loop(socket, target)
  end

  @impl true
  def handle_demand(type, _size, _unit, _ctx, %{stale_frame: {type, buffer}} = state) do
    # There is stale frame, which indicates that that the source was blocked waiting for demand from one of the outputs
    # It now arrived, so we request next frame and output the one that blocked us
    send(state.client_pid, :get_frame)
    {{:ok, buffer: {type, buffer}}, %{state | stale_frame: nil}}
  end

  @impl true
  def handle_demand(_type, _size, _unit, _ctx, state) do
    {:ok, state}
  end

  @impl true
  def handle_playing_to_prepared(_ctx, state) do
    send(state.client_pid, :terminate)
    Process.unlink(state.client_pid)
    {:ok, %{state | client_pid: nil}}
  end

  @impl true
  def handle_other({:tcp, client_socket, packet}, _context, state) do
    state = %{state | client_socket: client_socket}

    Logger.debug(
      "Source received a packet of length: #{byte_size(packet)}, handling with #{inspect(state.interceptor)}"
    )

    {messages, interceptor} = parse_packet_messages(packet, state.interceptor)
    {_cmd, state} = handle_client_messages(messages, state)

    {:ok, %{state | interceptor: interceptor}}
  end

  @impl true
  def handle_other(message, _context, state) do
    Logger.debug("Source received unknown message: #{inspect(message)}")
    {:ok, state}
  end

  defp request_packet(pid) do
    Logger.debug("Sending request to receiver")
    send(pid, :need_more_data)
  end

  defp handle_client_messages([], state) do
    request_packet(state.client_pid)

    {:noreply, state}
  end

  defp handle_client_messages(messages, state) do
    messages
    |> Enum.reduce_while({:ok, state}, fn message, acc ->
      do_handle_client_message(state.client_socket, message, acc)
    end)
    |> case do
      {:ok, %{client_connected?: true} = state} ->
        # once we are connected don't ask the client for new packets until a pipeline gets started
        {:noreply, state, {:continue, :start_pipeline}}

      {:ok, state} ->
        request_packet(state.client_socket)

        {:noreply, state}

      {:error, :stream_key_missing} ->
        Logger.error("Connection was missing stream key, closing...")

        {:stop, :normal, state}

      {:error, _reason} = error ->
        {:stop, error, state}
    end
  end

  # Expected flow of messages:
  # 1. [in] c0_c1 handshake -> [out] s0_s1_s2 handshake
  # 2. [in] c2 handshake -> [out] empty
  # 3. [in] set chunk size -> [out] empty
  # 4. [in] connect -> [out] window acknowledgement, set peer bandwidth, set chunk size, connect success, on bw done
  # 5. [in] release stream -> [out] default _result
  # 6. [in] FC publish, create stream, _checkbw -> [out] onFCPublish, default _result, default _result
  # 7. [in] release stream -> [out] _result response
  # 8. [in] publish -> [out] user control with stream id, pubish success
  # 9. CONNECTED
  defp do_handle_client_message(socket, message, {:ok, state}) do
    chunk_size = state.interceptor.out_chunk_size

    Logger.debug("Handling message: #{inspect(message)}")

    case message do
      %Handshake.Step{type: :s0_s1_s2} = step ->
        :gen_tcp.send(socket, Handshake.Step.serialize(step))

        connection_epoch = Handshake.Step.epoch(step)

        {:cont, {:ok, %{state | epoch: connection_epoch}}}

      %Messages.SetChunkSize{chunk_size: _chunk_size} ->
        {:cont, {:ok, state}}

      %Messages.Connect{} ->
        # the default value of ffmpeg server
        %Messages.WindowAcknowledgement{size: 2_500_000}
        |> send_rtmp_payload(socket, chunk_size)

        # the default value of ffmpeg server
        %Messages.SetPeerBandwidth{size: 2_500_000}
        |> send_rtmp_payload(socket, chunk_size)

        # stream begin type
        %Messages.UserControl{event_type: 0x00, data: <<0, 0, 0, 0>>}
        |> send_rtmp_payload(socket, chunk_size)

        # by default the ffmpeg server uses 128 chunk size
        %Messages.SetChunkSize{chunk_size: chunk_size}
        |> send_rtmp_payload(socket, chunk_size)

        {[tx_id], interceptor} = Interceptor.generate_tx_ids(state.interceptor, 1)

        tx_id
        |> Responses.connection_success()
        |> send_rtmp_payload(socket, chunk_size, chunk_stream_id: 3)

        Responses.on_bw_done()
        |> send_rtmp_payload(socket, chunk_size, chunk_stream_id: 3)

        {:cont, {:ok, %{state | interceptor: interceptor}}}

      %Messages.ReleaseStream{tx_id: tx_id, stream_key: _stream_key} ->
        tx_id
        |> Responses.default_result()
        |> send_rtmp_payload(socket, chunk_size, chunk_stream_id: 3)

        {:cont, {:ok, state}}

      # NOTE: For now we end parsing messages once we receive publish message.
      # At some point we may want to verify the stream parameters or simply extract
      # them for further processing.
      %Messages.SetDataFrame{} ->
        raise "Received @setDataFrame RTMP message when it should not be possible"

      %Messages.FCPublish{} ->
        %Messages.Anonymous{name: "onFCPublish", properties: []}
        |> send_rtmp_payload(socket, chunk_size, chunk_stream_id: 3)

        {:cont, {:ok, state}}

      %Messages.CreateStream{tx_id: tx_id} ->
        stream_id = [1.0]

        tx_id
        |> Responses.default_result(stream_id)
        |> send_rtmp_payload(socket, chunk_size, chunk_stream_id: 3)

        {:cont, {:ok, state}}

      %Messages.Anonymous{name: "_checkbw", tx_id: tx_id} ->
        tx_id
        |> send_rtmp_payload(socket, chunk_size, chunk_stream_id: 3)

        {:cont, {:ok, state}}
    end
  end

  defp send_rtmp_payload(message, socket, chunk_size, opts \\ []) do
    type = Serializer.type(message)
    body = Serializer.serialize(message)

    chunk_stream_id = Keyword.get(opts, :chunk_stream_id, 2)

    header =
      [chunk_stream_id: 2, type_id: type, body_size: byte_size(body)]
      |> Keyword.merge(opts)
      |> Header.new()
      |> Header.serialize()

    payload = Message.chunk_payload(body, chunk_stream_id, chunk_size)

    :gen_tcp.send(socket, [header | payload])
  end

  # The RTMP connection is based on TCP therefore we are operating on a continuous stream of bytes.
  # In such case packets received on TCP sockets may contain a partial RTMP packet or several full packets.
  #
  # `Interceptor` is already able to request more data if packet is incomplete but it is not aware
  # if its current buffer contains more than one message, therefore we need to call the `&Interceptor.handle_packet/2`
  # as long as we decide to receive more messages (before starting to relay media packets).
  #
  # Once we hit `:need_more_data` the function returns the list of parsed messages and the interceptor then is ready
  # to receive more data to continue with emitting new messages.
  @spec parse_packet_messages(packet :: binary(), interceptor :: struct(), [any()]) ::
          {[Message.t()], interceptor :: struct()}
  defp parse_packet_messages(packet, interceptor, messages \\ [])

  defp parse_packet_messages(<<>>, %{buffer: <<>>} = interceptor, messages) do
    {Enum.reverse(messages), interceptor}
  end

  defp parse_packet_messages(packet, interceptor, messages) do
    case Interceptor.handle_packet(packet, interceptor) do
      {_header, message, interceptor} ->
        parse_packet_messages(<<>>, interceptor, [message | messages])

      {:need_more_data, interceptor} ->
        {Enum.reverse(messages), interceptor}

      {:handshake_done, interceptor} ->
        parse_packet_messages(<<>>, interceptor, messages)

      {%Handshake.Step{} = step, interceptor} ->
        parse_packet_messages(<<>>, interceptor, [step | messages])
    end
  end
end
