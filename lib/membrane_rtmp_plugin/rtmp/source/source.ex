defmodule Membrane.RTMP.Source do
  @moduledoc """
  Membrane Element for receiving RTMP streams. Acts as a RTMP Server.
  This implementation is limited to only AAC and H264 streams.
  """
  use Membrane.Source

  require Membrane.Logger

  alias Membrane.{Buffer, Time, Logger}
  alias Membrane.RTMP.{Interceptor, Handshake, Header, Message, Messages, Responses}
  alias Membrane.RTMP.Messages.Serializer

  def_output_pad :output,
    availability: :always,
    caps: Membrane.RemoteStream,
    mode: :pull

  def_options port: [
                spec: non_neg_integer(),
                description: """
                Port on which the server will be listen
                """
              ],
              local_ip: [
                spec: binary(),
                default: "127.0.0.1",
                description:
                  "IP address on which the server will listen. This is useful if you have more than one network interface"
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
       buffers: [],
       header_sent?: false,
       interceptor: Interceptor.init(Handshake.init_server()),
       client_pid: nil,
       client_socket: nil,
       client_connected?: false,
       # epoch required for performing a handshake with the pipeline
       epoch: 0
     })}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    target_pid = self()

    pid =
      spawn_link(fn ->
        {:ok, socket} =
          :gen_tcp.listen(state.port, [
            :binary,
            packet: :raw,
            active: :once,
            reuseaddr: true,
            ip:
              state.local_ip
              |> String.split(".")
              |> Enum.map(&String.to_integer/1)
              |> List.to_tuple()
          ])

        Logger.debug("established tcp connection")

        {:ok, client} = :gen_tcp.accept(socket)

        receive_loop(client, target_pid)
      end)

    actions = [
      caps: {:output, %Membrane.RemoteStream{content_format: Membrane.FLV, type: :bytestream}}
    ]

    {{:ok, actions}, %{state | client_pid: pid}}
  end

  defp receive_loop(socket, target) do
    receive do
      :need_more_data ->
        :inet.setopts(socket, active: :once)

      {:tcp, _port, packet} ->
        send(target, {:tcp, socket, packet})

      {:tcp_closed, _port} ->
        send(target, {:tcp_closed, socket})

      :terminate ->
        exit(:normal)

      message ->
        Logger.debug("Receiver got unknown message: #{inspect(message)}")
        :noop
    end

    receive_loop(socket, target)
  end

  @impl true
  def handle_demand(_pad, _size, _unit, _ctx, state) do
    send(state.client_pid, :need_more_data)
    {:ok, state}
  end

  @impl true
  def handle_playing_to_prepared(_ctx, state) do
    send(state.client_pid, :terminate)
    Process.unlink(state.client_pid)
    {:ok, %{state | client_pid: nil}}
  end

  @impl true
  def handle_other({:tcp, client_socket, packet}, _ctx, state) do
    state = %{state | client_socket: client_socket}

    {messages, interceptor} = parse_packet_messages(packet, state.interceptor)

    state = handle_client_messages(messages, state)
    {actions, state} = get_actions(state)

    {{:ok, actions}, %{state | interceptor: interceptor}}
  end

  @impl true
  def handle_other({:tcp_closed, _port}, _ctx, state) do
    {{:ok, end_of_stream: :output}, state}
  end

  @impl true
  def handle_other(message, _ctx, state) do
    Logger.debug("Source received unknown message: #{inspect(message)}")
    {:ok, state}
  end

  defp get_actions(state) do
    case state do
      %{buffers: [_buf | _rest] = buffers} ->
        {[buffer: {:output, Enum.reverse(buffers)}], %{state | buffers: []}}

      _ ->
        {[], state}
    end
  end

  defp request_packet(pid) do
    send(pid, :need_more_data)
  end

  defp handle_client_messages([], state) do
    request_packet(state.client_pid)
    state
  end

  defp handle_client_messages(messages, state) do
    messages
    |> Enum.reduce_while(state, fn message, acc ->
      do_handle_client_message(state.client_socket, message, acc)
    end)
    |> case do
      %{client_connected?: true} = state ->
        # once we are connected don't ask the client for new packets until a pipeline gets started
        state

      {:error, _reason} = error ->
        raise error

      state ->
        request_packet(state.client_pid)

        state
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
  # 8. [in] publish -> [out] user control with stream id, publish success
  # 9. CONNECTED
  defp do_handle_client_message(socket, {header, message}, state) do
    chunk_size = state.interceptor.chunk_size

    case message do
      %Handshake.Step{type: :s0_s1_s2} = step ->
        :gen_tcp.send(socket, Handshake.Step.serialize(step))

        connection_epoch = Handshake.Step.epoch(step)
        {:cont, %{state | epoch: connection_epoch}}

      %Messages.SetChunkSize{chunk_size: _chunk_size} ->
        {:cont, state}

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

        {:cont, %{state | interceptor: interceptor}}

      %Messages.ReleaseStream{tx_id: tx_id, stream_key: _stream_key} ->
        tx_id
        |> Responses.default_result()
        |> send_rtmp_payload(socket, chunk_size, chunk_stream_id: 3)

        {:cont, state}

      %Messages.Publish{stream_key: stream_key, publish_type: "live"} ->
        %Messages.UserControl{event_type: 0, data: <<0, 0, 0, 1>>}
        |> send_rtmp_payload(socket, chunk_size, chunk_stream_id: 3)

        Responses.publish_success(stream_key)
        |> send_rtmp_payload(socket, chunk_size, chunk_stream_id: 3)

        {:halt, state}

      %Messages.Publish{publish_type: _publish_type} ->
        {:halt, {:error, :invalid_publish_type}}

      # NOTE: For now we end parsing messages once we receive publish message.
      # At some point we may want to verify the stream parameters or simply extract
      # them for further processing.
      %Messages.SetDataFrame{} ->
        # raise "Received @setDataFrame RTMP message when it should not be possible"
        {:cont, state}

      %Messages.FCPublish{} ->
        %Messages.Anonymous{name: "onFCPublish", properties: []}
        |> send_rtmp_payload(socket, chunk_size, chunk_stream_id: 3)

        {:cont, state}

      %Messages.CreateStream{tx_id: tx_id} ->
        stream_id = [1.0]

        tx_id
        |> Responses.default_result(stream_id)
        |> send_rtmp_payload(socket, chunk_size, chunk_stream_id: 3)

        {:cont, state}

      %Messages.Anonymous{name: "_checkbw", tx_id: tx_id} ->
        tx_id
        |> send_rtmp_payload(socket, chunk_size, chunk_stream_id: 3)

        {:cont, state}

      %Messages.Audio{data: data} ->
        Logger.debug("source received audio message")

        {buffers, state} = get_media_buffers(header, data, state)
        {:cont, %{state | buffers: buffers}}

      %Messages.Video{data: data} ->
        Logger.debug("source received video message")

        {buffers, state} = get_media_buffers(header, data, state)
        {:cont, %{state | buffers: buffers}}

      %Messages.Anonymous{name: "deleteStream"} ->
        Logger.debug("Received deleteStream messaage")
        {:cont, state}

      %Messages.Anonymous{} = message ->
        Logger.debug("Unknown message: #{inspect(message)}")

        {:cont, state}
    end
  end

  defp get_media_buffers(header, data, state) do
    payload =
      case state.header_sent? do
        false ->
          get_flv_header()

        true ->
          <<>>
      end <> get_flv_body(header, data)

    buffers = [%Buffer{payload: payload} | state[:buffers]]
    Logger.debug("media buffer: #{inspect(%Buffer{payload: payload})}")
    {buffers, %{state | header_sent?: true}}
  end

  defp get_flv_header() do
    <<"FLV", 0x01::8, 0::5, 1::1, 0::1, 1::1, 9::32>>
  end

  defp get_flv_body(
         %Membrane.RTMP.Header{
           #  chunk_stream_id: stream_id,
           timestamp: timestamp,
           body_size: data_size,
           type_id: type_id,
           stream_id: stream_id
         },
         payload
       ) do
    <<0::32, type_id::8, data_size::24, timestamp::24, 0::8, stream_id::24,
      payload::binary-size(data_size)>>
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
      {header, message, interceptor} ->
        parse_packet_messages(<<>>, interceptor, [{header, message} | messages])

      {:need_more_data, interceptor} ->
        {Enum.reverse(messages), interceptor}

      {:handshake_done, interceptor} ->
        parse_packet_messages(<<>>, interceptor, messages)

      {%Handshake.Step{} = step, interceptor} ->
        parse_packet_messages(<<>>, interceptor, [{nil, step} | messages])
    end
  end
end
