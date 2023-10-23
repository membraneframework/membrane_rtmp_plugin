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

  @windows_acknowledgment_size 2_500_000
  @peer_bandwidth_size 2_500_000

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
  # 1. [in] c0_c1 handshake -> [out] s0_s1_s2 handshake
  # 2. [in] c2 handshake -> [out] empty
  # 3. [in] set chunk size -> [out] empty
  # 4. [in] connect -> [out] window acknowledgement, set peer bandwidth, set chunk size, connect success, on bw done
  # 5. [in] release stream -> [out] default _result
  # 6. [in] FC publish, create stream, _checkbw -> [out] onFCPublish, default _result, default _result
  # 7. [in] release stream -> [out] _result response
  # 8. [in] publish -> [out] user control with stream id, publish success
  # 9. CONNECTED

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

  @validation_stage :connect
  defp do_handle_client_message(%Messages.Connect{} = msg, _header, state) do
    case MessageValidator.validate_connect(state.validator, msg) do
      {:ok, _msg} = result ->
        chunk_size = state.message_parser.chunk_size

        [
          %Messages.WindowAcknowledgement{size: @windows_acknowledgment_size},
          %Messages.SetPeerBandwidth{size: @peer_bandwidth_size},
          # stream begin type
          %Messages.UserControl{event_type: 0x00, data: <<0, 0, 0, 0>>},
          # by default the ffmpeg server uses 128 chunk size
          %Messages.SetChunkSize{chunk_size: chunk_size}
        ]
        |> Enum.each(&send_rtmp_payload(&1, state.socket, chunk_size))

        {[tx_id], message_parser} = MessageParser.generate_tx_ids(state.message_parser, 1)

        tx_id
        |> Responses.connection_success()
        |> send_rtmp_payload(state.socket, chunk_size, chunk_stream_id: 3)

        Responses.on_bw_done()
        |> send_rtmp_payload(state.socket, chunk_size, chunk_stream_id: 3)

        {:cont,
         validation_action(%{state | message_parser: message_parser}, @validation_stage, result)}

      {:error, _reason} = error ->
        {:halt, {:error, :stream_validation, validation_action(state, @validation_stage, error)}}
    end
  end

  # According to ffmpeg's documentation, this command should make the server release channel for a media stream
  # We are simply acknowleding the message
  @validation_stage :release_stream
  defp do_handle_client_message(
         %Messages.ReleaseStream{tx_id: tx_id} = msg,
         _header,
         state
       ) do
    case MessageValidator.validate_release_stream(state.validator, msg) do
      {:ok, _msg} = result ->
        tx_id
        |> Responses.default_result()
        |> send_rtmp_payload(state.socket, state.message_parser.chunk_size, chunk_stream_id: 3)

        {:cont, validation_action(state, @validation_stage, result)}

      {:error, _reason} = error ->
        {:halt, {:error, :stream_validation, validation_action(state, @validation_stage, error)}}
    end
  end

  @validation_stage :publish
  defp do_handle_client_message(
         %Messages.Publish{stream_key: stream_key} = msg,
         _header,
         state
       ) do
    case MessageValidator.validate_publish(state.validator, msg) do
      {:ok, _msg} = result ->
        %Messages.UserControl{event_type: 0, data: <<0, 0, 0, 1>>}
        |> send_rtmp_payload(state.socket, state.message_parser.chunk_size, chunk_stream_id: 3)

        Responses.publish_success(stream_key)
        |> send_rtmp_payload(state.socket, state.message_parser.chunk_size, chunk_stream_id: 3)

        {:cont, validation_action(state, @validation_stage, result)}

      {:error, _reason} = error ->
        {:halt, {:error, :stream_validation, validation_action(state, @validation_stage, error)}}
    end
  end

  # A message containing stream metadata
  @validation_stage :set_data_frame
  defp do_handle_client_message(%Messages.SetDataFrame{} = msg, _header, state) do
    case MessageValidator.validate_set_data_frame(state.validator, msg) do
      {:ok, _msg} = result ->
        {:cont, validation_action(state, @validation_stage, result)}

      {:error, _reason} = error ->
        {:halt, {:error, :stream_validation, validation_action(state, @validation_stage, error)}}
    end
  end

  # According to ffmpeg's documentation, this command should prepare the server to receive media streams
  # We are simply acknowleding the message
  defp do_handle_client_message(%Messages.FCPublish{}, _header, state) do
    %Messages.Anonymous{name: "onFCPublish", properties: []}
    |> send_rtmp_payload(state.socket, state.message_parser.chunk_size, chunk_stream_id: 3)

    {:cont, state}
  end

  defp do_handle_client_message(%Messages.CreateStream{tx_id: tx_id}, _header, state) do
    stream_id = [1.0]

    tx_id
    |> Responses.default_result(stream_id)
    |> send_rtmp_payload(state.socket, state.message_parser.chunk_size, chunk_stream_id: 3)

    {:cont, state}
  end

  defp do_handle_client_message(%Messages.WindowAcknowledgement{}, _header, state) do
    Logger.warning(
      "Received WindowAcknowledgement from a client. Acknowledgments are currently not supported"
    )

    {:cont, state}
  end

  # Check bandwidth message
  defp do_handle_client_message(
         %Messages.Anonymous{name: "_checkbw", tx_id: tx_id},
         _header,
         state
       ) do
    tx_id
    |> send_rtmp_payload(state.socket, state.message_parser.chunk_size, chunk_stream_id: 3)

    {:cont, state}
  end

  defp do_handle_client_message(%Messages.Anonymous{name: "deleteStream"}, _header, state) do
    {:cont, %{state | actions: [{:end_of_stream, :output} | state.actions]}}
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

  defp get_media_actions(rtmp_header, data, state) do
    payload =
      get_flv_tag(rtmp_header, data)
      |> (&if(state.header_sent?, do: &1, else: get_flv_header() <> &1)).()

    actions = [{:buffer, {:output, %Buffer{payload: payload}}} | state.actions]
    %{state | header_sent?: true, actions: actions}
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
           type_id: type_id,
           stream_id: stream_id
         },
         payload
       ) do
    tag_size = data_size + 11

    <<upper_timestamp::8, lower_timestamp::24>> = <<timestamp::32>>

    <<type_id::8, data_size::24, lower_timestamp::24, upper_timestamp::8, stream_id::24,
      payload::binary-size(data_size), tag_size::32>>
  end

  defp send_rtmp_payload(message, socket, chunk_size, opts \\ []) do
    type = Serializer.type(message)
    body = Serializer.serialize(message)

    chunk_stream_id = Keyword.get(opts, :chunk_stream_id, 2)

    header =
      [chunk_stream_id: chunk_stream_id, type_id: type, body_size: byte_size(body)]
      |> Keyword.merge(opts)
      |> Header.new()
      |> Header.serialize()

    payload = Message.chunk_payload(body, chunk_stream_id, chunk_size)

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
