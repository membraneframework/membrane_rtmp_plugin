defmodule BroadcastEngine.Proxy.ConnectionHandler do
  @moduledoc """
  RTMP proxy connection handler.

  The main responsibility of #{inspect(__MODULE__)} is to:
  - authorize the incoming client connection
  - start a media pipeline when the client gets authorized
  - relay packets from/to client and pipeline sockets


  The goal is to postpone pipeilne start until the user gets
  authorized. #{inspect(__MODULE__)} does so by simulating the server
  socket messages and once authorized it simulates the client to get through
  the RTMP connecting process. When both connections are ready then
  the handler simply relays packets from one socket to another.
  """

  use GenServer

  import BroadcastEngine.Helpers

  require BroadcastEngine.RTMP.Header
  require Logger

  alias BroadcastEngine.RTMP
  alias BroadcastEngine.RTMP.{Header, Interceptor, Message, Messages}
  alias BroadcastEngine.RTMP.Messages.Serializer

  @spec start(any()) :: GenServer.on_start()
  def start(client_socket) do
    GenServer.start(__MODULE__, [client_socket])
  end

  @impl true
  def init([client_socket]) do
    # make the start asynchronous so that the client socket can
    # get assigned to the handler by outside process
    {:ok,
     %{
       client_socket: client_socket,
       server_socket: nil,
       # client interceptor inspects the traffic from a remote client (connection handler imitates an RTMP server)
       client_interceptor: Interceptor.init(RTMP.Handshake.init_server()),
       # server interceptor inspects the traffic from the media pipeline (connection handler imitates an RTMP client)
       server_interceptor: nil,
       client_connected?: false,
       server_connected?: false,
       stream_key: nil,
       broadcast_started?: false,
       # epoch required for performing a handshake with the pipeline
       epoch: 0
     }}
  end

  @impl true
  def handle_info(
        {:tcp, client_socket, data},
        %{client_socket: client_socket, server_socket: server_socket, client_connected?: true} =
          state
      ) do
    send_packet(client_socket, server_socket, data)

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:tcp, server_socket, data},
        %{server_socket: server_socket, client_socket: client_socket, server_connected?: true} =
          state
      ) do
    send_packet(server_socket, client_socket, data)

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:tcp, client_socket, data},
        %{client_socket: client_socket} = state
      ) do
    data
    |> parse_packet_messages(state.client_interceptor)
    |> then(fn {messages, interceptor} ->
      handle_client_messages(messages, %{state | client_interceptor: interceptor})
    end)
  end

  @impl true
  def handle_info(
        {:tcp, server_socket, data},
        %{server_socket: server_socket} = state
      ) do
    data
    |> parse_packet_messages(state.server_interceptor)
    |> then(fn {messages, interceptor} ->
      handle_server_messages(messages, %{state | server_interceptor: interceptor})
    end)
  end

  @impl true
  def handle_info(
        {:tcp_closed, client_socket},
        %{client_socket: client_socket, server_socket: server_socket} = state
      ) do
    unless is_nil(server_socket) do
      :ok = :gen_tcp.shutdown(server_socket, :read_write)
    end

    wait_for_broadcast_end(state)
  end

  @impl true
  def handle_info(
        {:tcp_closed, server_socket},
        %{client_socket: client_socket, server_socket: server_socket} = state
      ) do
    :ok = :gen_tcp.shutdown(client_socket, :read_write)

    wait_for_broadcast_end(state)
  end

  @impl true
  def handle_info(:broadcast_started, state) do
    Logger.info("#{log_prefix()} Broadcast has started for a stream key = #{state.stream_key}")
    {:noreply, %{state | broadcast_started?: true}}
  end

  @impl true
  def handle_continue(:start_pipeline, %{stream_key: stream_key} = state) do
    with {:ok, pipeline_port, pipeline} <-
           BroadcastEngine.BroadcastObserver.start_broadcast(random_streamer_id(),
             port: :discover,
             stream_key: stream_key,
             notification_listener: self()
           ),
         true <- Process.link(pipeline),
         {:ok, pipeline_socket} <- connect_with_pipeline(pipeline_port) do
      # start RTMP connection process
      # by sending the handshake (faking client side)

      {handshake_step, handshake} = RTMP.Handshake.init_client(state.epoch)

      handshake_payload = RTMP.Handshake.Step.serialize(handshake_step)

      :gen_tcp.send(pipeline_socket, handshake_payload)

      request_packet(pipeline_socket)

      server_interceptor =
        handshake
        |> Interceptor.init()
        |> Interceptor.update_out_chunk_size(state.client_interceptor.in_chunk_size)

      state =
        state
        |> Map.merge(%{
          server_socket: pipeline_socket,
          pipeline: pipeline
        })
        |> Map.replace!(:server_interceptor, server_interceptor)

      {:noreply, state}
    else
      _other ->
        raise "Failed to start the handler"
    end
  end

  @impl true
  def handle_continue(_message, state), do: {:noreply, state}

  @impl true
  def terminate(reason, _state) do
    Logger.debug("#{log_prefix()} Terminating with reason: #{inspect(reason)}")

    :ok
  end

  defp send_packet(from_socket, to_socket, data) do
    :gen_tcp.send(to_socket, data)

    :ok = :inet.setopts(from_socket, active: :once)
  end

  defp request_packet(socket) do
    :inet.setopts(socket, active: :once)
  end

  defp handle_client_messages([], state) do
    request_packet(state.client_socket)

    {:noreply, state}
  end

  defp handle_client_messages(messages, state) do
    %{client_socket: socket} = state

    messages
    |> Enum.reduce_while({:ok, state}, fn message, acc ->
      do_handle_client_message(socket, message, acc)
    end)
    |> case do
      {:ok, %{client_connected?: true} = state} ->
        # once we are connected don't ask the client for new packets until a pipeline gets started
        {:noreply, state, {:continue, :start_pipeline}}

      {:ok, state} ->
        request_packet(state.client_socket)

        {:noreply, state}

      {:error, :stream_key_missing} ->
        Logger.error("#{log_prefix()} Connection was missing stream key, closing...")

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
    chunk_size = state.client_interceptor.out_chunk_size

    case message do
      %RTMP.Handshake.Step{type: :s0_s1_s2} = step ->
        :gen_tcp.send(socket, RTMP.Handshake.Step.serialize(step))

        connection_epoch = RTMP.Handshake.Step.epoch(step)

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

        {[tx_id], interceptor} = Interceptor.generate_tx_ids(state.client_interceptor, 1)

        tx_id
        |> RTMP.Responses.connection_success()
        |> send_rtmp_payload(socket, chunk_size, chunk_stream_id: 3)

        RTMP.Responses.on_bw_done()
        |> send_rtmp_payload(socket, chunk_size, chunk_stream_id: 3)

        {:cont, {:ok, %{state | client_interceptor: interceptor}}}

      %Messages.ReleaseStream{tx_id: tx_id, stream_key: _stream_key} ->
        tx_id
        |> RTMP.Responses.default_result()
        |> send_rtmp_payload(socket, chunk_size, chunk_stream_id: 3)

        {:cont, {:ok, state}}

      %Messages.Publish{stream_key: stream_key, publish_type: "live"} ->
        case authorize_stream_key(stream_key, state) do
          {:ok, state} ->
            %Messages.UserControl{event_type: 0, data: <<0, 0, 0, 1>>}
            |> send_rtmp_payload(socket, chunk_size, chunk_stream_id: 3)

            RTMP.Responses.publish_success(stream_key)
            |> send_rtmp_payload(socket, chunk_size, chunk_stream_id: 3)

            {:halt, {:ok, state}}

          {:error, _reason} = error ->
            {:halt, error}
        end

      %Messages.Publish{publish_type: _publish_type} ->
        {:halt, {:error, :invalid_publish_type}}

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
        |> RTMP.Responses.default_result(stream_id)
        |> send_rtmp_payload(socket, chunk_size, chunk_stream_id: 3)

        {:cont, {:ok, state}}

      %Messages.Anonymous{name: "_checkbw", tx_id: tx_id} ->
        tx_id
        |> send_rtmp_payload(socket, chunk_size, chunk_stream_id: 3)

        {:cont, {:ok, state}}
    end
  end

  defp handle_server_messages([], state) do
    request_packet(state.server_socket)

    {:noreply, state}
  end

  defp handle_server_messages(messages, state) do
    %{server_socket: socket} = state

    messages
    |> Enum.reduce_while({:ok, state}, fn message, acc ->
      do_handle_server_message(socket, message, acc)
    end)
    |> case do
      {:ok, %{server_connected?: true} = state} ->
        # when server is connected finally request the client socket

        # connection to the server has been successful
        # query the server and client for next packets and
        # start relaying multimedia packets without
        # futher connection interception
        request_packet(state.client_socket)
        request_packet(state.server_socket)

        # in case the client interceptor has some data cached
        # send it straight away to the server
        packet = state.client_interceptor.buffer

        if byte_size(packet) > 0 do
          send_packet(state.client_socket, state.server_socket, packet)
        end

        # we no longer need the interceptors
        {:noreply, %{state | server_interceptor: nil, client_interceptor: nil}}

      {:ok, state} ->
        # the connection status has not changed, request new packet
        request_packet(state.server_socket)

        {:noreply, state}

      {:error, _reason} = error ->
        {:stop, error, state}
    end
  end

  # Expected flow of messages:
  # 0. Send c0_c1 handshake to pipeline to start connection process
  # 1. [in]  s0_s1_s2 (changed internally by interceptor to c2) -> [out] c2 handshake, set chunk size, connect
  # 2. [in] window acknowledgement, set peer bandwidth, user control (stream 0), set chunk size -> [out] empty
  # 4. [in] connection success -> [out] release stream, FCPublish, create stream, _checkbw 
  # 5. [in] a bunch of _result messages, user control (stream 1), stream published -> [out] empty
  # 6. CONNECTED
  defp do_handle_server_message(socket, message, {:ok, state}) do
    chunk_size = state.server_interceptor.out_chunk_size

    case message do
      %BroadcastEngine.RTMP.Handshake.Step{type: :c2} = step ->
        :gen_tcp.send(socket, RTMP.Handshake.Step.serialize(step))

        %Messages.SetChunkSize{chunk_size: chunk_size}
        |> send_rtmp_payload(socket, chunk_size)

        %Messages.Connect{
          app: "app",
          type: "nonprivate",
          supports_go_away: true,
          flash_version: "FMLE/3.0 (compatible; FMSc/1.0)",
          swf_url: "rtmp://localhost:9100/app",
          tc_url: "rtmp://localhost:9100/app"
        }
        |> send_rtmp_payload(socket, chunk_size)

        {:cont, {:ok, state}}

      %Messages.WindowAcknowledgement{size: _chunk_size} ->
        {:cont, {:ok, state}}

      %Messages.SetPeerBandwidth{size: _size} ->
        {:cont, {:ok, state}}

      # stream begin event
      %Messages.UserControl{event_type: 0, data: <<0, 0, 0, 0>>} ->
        {:cont, {:ok, state}}

      # stream published event
      %Messages.UserControl{event_type: 0, data: <<0, 0, 0, 1>>} ->
        {:cont, {:ok, state}}

      %Messages.SetChunkSize{chunk_size: _size} ->
        {:cont, {:ok, state}}

      %Messages.Anonymous{
        name: "_result",
        properties: [_properties, %{"code" => "NetConnection.Connect.Success"} = _information]
      } ->
        {[tx1, tx2, tx3, tx4], interceptor} =
          Interceptor.generate_tx_ids(state.server_interceptor, 4)

        %Messages.ReleaseStream{stream_key: state.stream_key, tx_id: tx1}
        |> send_rtmp_payload(socket, chunk_size, chunk_stream_id: 3)

        %Messages.FCPublish{stream_key: state.stream_key, tx_id: tx2}
        |> send_rtmp_payload(socket, chunk_size, chunk_stream_id: 3)

        %Messages.CreateStream{tx_id: tx3}
        |> send_rtmp_payload(socket, chunk_size, chunk_stream_id: 3)

        %Messages.Anonymous{name: "_checkbw", tx_id: tx4, properties: [:null]}
        |> send_rtmp_payload(socket, chunk_size, chunk_stream_id: 3)

        {:cont, {:ok, %{state | server_interceptor: interceptor}}}

      %Messages.Anonymous{name: "_result", properties: _properties} ->
        {:cont, {:ok, state}}

      %Messages.Anonymous{name: "onFCPublish", properties: _properties} ->
        {[tx_id], interceptor} = Interceptor.generate_tx_ids(state.server_interceptor, 1)

        %Messages.Publish{stream_key: state.stream_key, tx_id: tx_id, publish_type: "live"}
        |> send_rtmp_payload(socket, chunk_size, chunk_stream_id: 3)

        {:cont, {:ok, %{state | server_interceptor: interceptor}}}

      %Messages.Anonymous{
        name: "onStatus",
        tx_id: 0.0,
        properties: [:null, %{"code" => "NetStream.Publish.Start"}]
      } ->
        {:halt, {:ok, %{state | server_connected?: true}}}

      %Messages.Anonymous{name: "onBWDone"} ->
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

  # if any of the sockets has closed and the broadcast has already started
  # then wait for the `broadcast_ended` notification sent from the pipeline
  defp wait_for_broadcast_end(%{broadcast_started?: true} = state) do
    receive do
      :broadcast_ended ->
        Logger.info("#{log_prefix()} Broadcast has ended for stream key = #{state.stream_key}")

        {:stop, :normal, state}
    after
      5_000 ->
        {:stop, {:error, :broadcast_end_missing}, state}
    end
  end

  defp wait_for_broadcast_end(state), do: {:stop, :normal, state}

  @pipeline_connect_retries 3
  defp connect_with_pipeline(port, retries \\ @pipeline_connect_retries)

  defp connect_with_pipeline(_port, 0), do: {:error, :pipeline_unreachable}

  defp connect_with_pipeline(port, retries) do
    params = [{:inet_backend, :socket}, :binary, nodelay: true, packet: :raw, active: :once]

    case :gen_tcp.connect('127.0.0.1', port, params) do
      {:ok, pipeline_socket} ->
        {:ok, pipeline_socket}

      {:error, _reason} ->
        # retry with exponential backoff
        :timer.sleep(100 * round(:math.pow(2, @pipeline_connect_retries - retries + 1)))

        connect_with_pipeline(port, retries - 1)
    end
  end

  # NOTE: this should be an entry point for validating the stream key
  # for now just pass any key that is non-empty
  defp authorize_stream_key(stream_key, state) do
    if stream_key == "" do
      {:error, :stream_key_missing}
    else
      {:ok, %{state | stream_key: stream_key, client_connected?: true}}
    end
  end

  # The RTMP connection is based on TCP therefore we are operating on a continious stream of bytes.
  # In such case packets received on TCP sockets may contain a partial RTMP packet or several full packets. 
  # 
  # `Interceptor` is already able to request more data if packet is incomplete but it is not aware
  # if its current bffer contains more than one message, therefore we need to call the `&Interceptor.handle_packet/2`
  # as long as we decide to receive more messages (before starting to relay media packets). 
  #
  # Once we hit `:need_more_data` the function returns the list of parsed messages and the interceptor then is ready
  # to receive more data to continue with emitting new messages.
  @spec parse_packet_messages(packet :: binary(), interceptor :: struct(), [any()]) ::
          {[Message.t()], interceptor :: struct()}
  defp parse_packet_messages(packet, interceptor, messages \\ [])

  defp parse_packet_messages(<<>>, %{buffer: <<>>} = interceptor, messages),
    do: {Enum.reverse(messages), interceptor}

  defp parse_packet_messages(packet, interceptor, messages) do
    case Interceptor.handle_packet(packet, interceptor) do
      {_header, message, interceptor} ->
        parse_packet_messages(<<>>, interceptor, [message | messages])

      {:need_more_data, interceptor} ->
        {Enum.reverse(messages), interceptor}

      {:handshake_done, interceptor} ->
        parse_packet_messages(<<>>, interceptor, messages)

      {%RTMP.Handshake.Step{} = step, interceptor} ->
        parse_packet_messages(<<>>, interceptor, [step | messages])
    end
  end

  defp random_streamer_id(), do: "streamer_#{:rand.uniform(10_000)}"
end
