defmodule Membrane.RTMP.MessageHandler do
  @moduledoc false

  # Module responsible for processing the RTMP messages
  # Appropriate responses are sent to the messages received during the initialization phase
  # The data received in video and audio is forwarded to the outputs

  require Membrane.Logger

  alias Membrane.{Buffer, Logger}

  alias Membrane.RTMP.{
    Handshake,
    Header,
    Message,
    MessageParser,
    Messages,
    MessageValidator,
    Responses
  }

  alias Membrane.RTMP.Messages.Serializer

  # maxed out signed int32, we don't have acknowledgements implemented
  @window_acknowledgement_size 2_147_483_647
  @peer_bandwidth_size 2_147_483_647

  # just to not waste time on chunking
  @server_chunk_size 4096

  @spec handle_client_messages(list(), map()) :: map()
  def handle_client_messages([], state) do
    request_packet(state.socket)
    state
  end

  def handle_client_messages(messages, state) do
    messages
    |> Enum.reduce_while(state, fn {header, message}, acc ->
      do_handle_client_message(message, header, acc)
    end)
    |> case do
      {:error, :stream_validation, state} ->
        state.socket_module.shutdown(state.socket, :read_write)

        state

      state ->
        request_packet(state.socket)
        %{state | actions: Enum.reverse(state.actions)}
    end
  end

  # Expected flow of messages:
  # 1.  [in] c0_c1 handshake -> [out] s0_s1_s2 handshake
  # 2.  [in] c2 handshake -> [out] empty
  # 3.  [in] set chunk size -> [out] empty
  # 4.  [in] connect -> [out] set peer bandwidth, window acknowledgement, stream begin 0, set chunk size, connect _result, onBWDone
  # 5.  [in] release stream -> [out] _result
  # 6.  [in] FC publish, create stream -> [out] onFCPublish, _result
  # 8.  [in] publish -> [out] stream begin 1, onStatus publish
  # 9.  [in] setDataFrame, media data -> [out] empty
  # 10. CONNECTED

  defp do_handle_client_message(%module{data: data}, header, state)
       when module in [Messages.Audio, Messages.Video] do
    state = get_media_actions(header, data, state)
    {:cont, state}
  end

  defp do_handle_client_message(%Handshake.Step{type: :s0_s1_s2} = step, _header, state) do
    state.socket_module.send(state.socket, Handshake.Step.serialize(step))

    connection_epoch = Handshake.Step.epoch(step)
    {:cont, %{state | epoch: connection_epoch}}
  end

  defp do_handle_client_message(%Messages.SetChunkSize{chunk_size: chunk_size}, _header, state) do
    parser = %{state.message_parser | chunk_size: chunk_size}
    {:cont, %{state | message_parser: parser}}
  end

  @stream_begin_type 0
  @validation_stage :connect
  defp do_handle_client_message(%Messages.Connect{} = connect, _header, state) do
    case MessageValidator.validate_connect(state.validator, connect) do
      {:ok, _msg} = result ->
        [
          %Messages.WindowAcknowledgement{size: @window_acknowledgement_size},
          %Messages.SetPeerBandwidth{size: @peer_bandwidth_size},
          # stream begin type
          %Messages.UserControl{event_type: @stream_begin_type, data: <<0, 0, 0, 0>>},
          # the chunk size is independent for both sides
          %Messages.SetChunkSize{chunk_size: @server_chunk_size}
        ]
        |> Enum.each(&send_rtmp_payload(&1, state.socket, chunk_stream_id: 2))

        Responses.connection_success()
        |> send_rtmp_payload(state.socket, chunk_stream_id: 3)

        Responses.on_bw_done()
        |> send_rtmp_payload(state.socket, chunk_stream_id: 3)

        {:cont, validation_action(state, @validation_stage, result)}

      {:error, _reason} = error ->
        {:halt, {:error, :stream_validation, validation_action(state, @validation_stage, error)}}
    end
  end

  # According to ffmpeg's documentation, this command should make the server release channel for a media stream
  # We are simply acknowledging the message
  @validation_stage :release_stream
  defp do_handle_client_message(%Messages.ReleaseStream{} = release_stream, _header, state) do
    case MessageValidator.validate_release_stream(state.validator, release_stream) do
      {:ok, _msg} = result ->
        release_stream.tx_id
        |> Responses.default_result([0.0, :null])
        |> send_rtmp_payload(state.socket, chunk_stream_id: 3)

        {:cont, validation_action(state, @validation_stage, result)}

      {:error, _reason} = error ->
        {:halt, {:error, :stream_validation, validation_action(state, @validation_stage, error)}}
    end
  end

  @validation_stage :publish
  defp do_handle_client_message(%Messages.Publish{} = publish, %Header{} = header, state) do
    case MessageValidator.validate_publish(state.validator, publish) do
      {:ok, _msg} = result ->
        %Messages.UserControl{event_type: @stream_begin_type, data: <<0, 0, 0, 1>>}
        |> send_rtmp_payload(state.socket, chunk_stream_id: 2)

        Responses.publish_success(publish.stream_key)
        |> send_rtmp_payload(state.socket, chunk_stream_id: 3, stream_id: header.stream_id)

        {:cont, validation_action(state, @validation_stage, result)}

      {:error, _reason} = error ->
        {:halt, {:error, :stream_validation, validation_action(state, @validation_stage, error)}}
    end
  end

  # A message containing stream metadata
  @validation_stage :set_data_frame
  defp do_handle_client_message(%Messages.SetDataFrame{} = data_frame, _header, state) do
    case MessageValidator.validate_set_data_frame(state.validator, data_frame) do
      {:ok, _msg} = result ->
        {:cont, validation_action(state, @validation_stage, result)}

      {:error, _reason} = error ->
        {:halt, {:error, :stream_validation, validation_action(state, @validation_stage, error)}}
    end
  end

  # According to ffmpeg's documentation, this command should prepare the server to receive media streams
  # We are simply acknowledging the message
  defp do_handle_client_message(%Messages.FCPublish{}, _header, state) do
    %Messages.Anonymous{name: "onFCPublish", properties: []}
    |> send_rtmp_payload(state.socket, chunk_stream_id: 3)

    {:cont, state}
  end

  defp do_handle_client_message(%Messages.CreateStream{} = create_stream, _header, state) do
    # following ffmpeg rtmp server implementation
    stream_id = 1.0

    create_stream.tx_id
    |> Responses.default_result([:null, stream_id])
    |> send_rtmp_payload(state.socket, chunk_stream_id: 3)

    {:cont, state}
  end

  # we ignore acknowledgement messages, but they're rarely used anyways
  defp do_handle_client_message(%module{}, _header, state)
       when module in [Messages.Acknowledgement, Messages.WindowAcknowledgement] do
    Logger.debug("#{inspect(module)} received, ignoring as acknowledgements are not implemented")

    {:cont, state}
  end

  @ping_request_type 6
  @ping_response_type 7
  # according to the spec this should be sent by server, but some clients send it anyway (restream.io)
  defp do_handle_client_message(
         %Messages.UserControl{event_type: @ping_request_type} = ping_request,
         _header,
         state
       ) do
    %Messages.UserControl{event_type: @ping_response_type, data: ping_request.data}
    |> send_rtmp_payload(state.socket, chunk_stream_id: 2)

    {:cont, state}
  end

  defp do_handle_client_message(%Messages.DeleteStream{}, _header, state) do
    {:halt, %{state | actions: [{:end_of_stream, :output} | state.actions]}}
  end

  # Check bandwidth message
  defp do_handle_client_message(%Messages.Anonymous{name: "_checkbw"} = msg, _header, state) do
    # the message doesn't belong to spec, let's just follow this implementation
    # https://github.com/use-go/wsa/blob/b4d0808fe5b6daff1c381d5127bbd450168230a1/rtmp/RTMP.go#L1014
    msg.tx_id
    |> Responses.default_result([:null, 0.0])
    |> send_rtmp_payload(state.socket, chunk_stream_id: 3)

    {:cont, state}
  end

  defp do_handle_client_message(%Messages.Anonymous{} = message, _header, state) do
    Logger.debug("Unknown message: #{inspect(message)}")

    {:cont, state}
  end

  defp request_packet({:sslsocket, _1, _2} = socket) do
    :ssl.setopts(socket, active: :once)
  end

  defp request_packet(socket) do
    :inet.setopts(socket, active: :once)
  end

  defp get_media_actions(rtmp_header, data, %{header_sent?: true} = state) do
    payload = get_flv_tag(rtmp_header, data)

    Map.update!(state, :actions, &[{:buffer, {:output, %Buffer{payload: payload}}} | &1])
  end

  defp get_media_actions(rtmp_header, data, state) do
    payload = get_flv_header() <> get_flv_tag(rtmp_header, data)

    %{
      state
      | header_sent?: true,
        actions: [{:buffer, {:output, %Buffer{payload: payload}}} | state.actions]
    }
  end

  defp get_flv_header() do
    alias Membrane.FLV

    {header, 0} =
      FLV.Serializer.serialize(%FLV.Header{audio_present?: true, video_present?: true}, 0)

    # Add PreviousTagSize, which is 0 for the first tag
    header <> <<0::32>>
  end

  defp get_flv_tag(
         %Membrane.RTMP.Header{
           timestamp: timestamp,
           body_size: data_size,
           type_id: type_id
         },
         payload
       ) do
    tag_size = data_size + 11

    <<upper_timestamp::8, lower_timestamp::24>> = <<timestamp::32>>

    # according to the FLV spec, the stream ID should always be 0
    stream_id = 0

    <<type_id::8, data_size::24, lower_timestamp::24, upper_timestamp::8, stream_id::24,
      payload::binary-size(data_size), tag_size::32>>
  end

  defp send_rtmp_payload(message, socket, opts) do
    type = Serializer.type(message)
    body = Serializer.serialize(message)

    chunk_stream_id = Keyword.get(opts, :chunk_stream_id, 2)

    header =
      [chunk_stream_id: chunk_stream_id, type_id: type, body_size: byte_size(body)]
      |> Keyword.merge(opts)
      |> Header.new()
      |> Header.serialize()

    payload = Message.chunk_payload(body, chunk_stream_id, @server_chunk_size)

    socket_module(socket).send(socket, [header | payload])
  end

  defp validation_action(state, stage, result) do
    notification =
      case result do
        {:ok, msg} -> {:notify_parent, {:stream_validation_success, stage, msg}}
        {:error, reason} -> {:notify_parent, {:stream_validation_error, stage, reason}}
      end

    Map.update!(state, :actions, &[notification | &1])
  end

  # The RTMP connection is based on TCP therefore we are operating on a continuous stream of bytes.
  # In such case packets received on TCP sockets may contain a partial RTMP packet or several full packets.
  #
  # `MessageParser` is already able to request more data if packet is incomplete but it is not aware
  # if its current buffer contains more than one message, therefore we need to call the `&MessageParser.handle_packet/2`
  # as long as we decide to receive more messages (before starting to relay media packets).
  #
  # Once we hit `:need_more_data` the function returns the list of parsed messages and the message_parser then is ready
  # to receive more data to continue with emitting new messages.
  @spec parse_packet_messages(packet :: binary(), message_parser :: struct(), [{any(), any()}]) ::
          {[Message.t()], message_parser :: struct()}
  def parse_packet_messages(packet, message_parser, messages \\ [])

  def parse_packet_messages(<<>>, %{buffer: <<>>} = message_parser, messages) do
    {Enum.reverse(messages), message_parser}
  end

  def parse_packet_messages(packet, message_parser, messages) do
    case MessageParser.handle_packet(packet, message_parser) do
      {header, message, message_parser} ->
        parse_packet_messages(<<>>, message_parser, [{header, message} | messages])

      {:need_more_data, message_parser} ->
        {Enum.reverse(messages), message_parser}

      {:handshake_done, message_parser} ->
        parse_packet_messages(<<>>, message_parser, messages)

      {%Handshake.Step{} = step, message_parser} ->
        parse_packet_messages(<<>>, message_parser, [{nil, step} | messages])
    end
  end

  @compile {:inline, socket_module: 1}
  defp socket_module({:sslsocket, _1, _2}), do: :ssl
  defp socket_module(_other), do: :gen_tcp
end
