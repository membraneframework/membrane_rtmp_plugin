defmodule Membrane.RTMP.MessageHandler do
  @moduledoc false

  # Module responsible for processing the RTMP messages
  # Appropriate responses are sent to the messages received during the initialization phase
  # The data received in video and audio is forwarded to the outputs

  require Membrane.Logger, as: Logger

  alias Membrane.RTMP.{
    Handshake,
    Header,
    Message,
    Messages,
    Responses
  }

  alias Membrane.RTMP.Messages.Serializer

  # maxed out signed int32, we don't have acknowledgements implemented
  @window_acknowledgement_size 2_147_483_647
  @peer_bandwidth_size 2_147_483_647

  # just to not waste time on chunking
  @server_chunk_size 4096

  @type event() ::
          {:set_chunk_size_required, non_neg_integer()}
          | {:connected, Membrane.RTMP.Messages.Connect.t()}
          | {:published, Membrane.RTMP.Messages.Publish.t()}
          | :delete_stream
          | {:data_available, binary()}
  @type t() :: %{
          socket: :gen_tcp.socket() | :ssl.socket(),
          socket_module: :gen_tcp | :ssl,
          header_sent?: boolean(),
          events: [event()],
          receiver_pid: pid() | nil,
          socket_retries: pos_integer(),
          epoch: non_neg_integer(),
          publish_msg: Messages.Publish.t() | nil,
          publish_header: Header.t() | nil
        }

  @spec init(opts :: %{socket: :gen_tcp.socket() | :ssl.socket(), use_ssl?: boolean()}) :: t()
  def init(opts) do
    %{
      socket: opts.socket,
      socket_module: if(opts.use_ssl?, do: :ssl, else: :gen_tcp),
      header_sent?: false,
      events: [],
      receiver_pid: nil,
      publish_msg: nil,
      publish_header: nil,
      # how many times the Source tries to get control of the socket
      socket_retries: 3,
      # epoch required for performing a handshake with the pipeline
      epoch: 0
    }
  end

  @spec handle_client_messages(list(), map()) :: {map(), list()}
  def handle_client_messages([], state) do
    {%{state | events: []}, state.events}
  end

  def handle_client_messages(messages, state) do
    messages
    |> Enum.reduce_while(state, fn {header, message}, acc ->
      do_handle_client_message(message, header, acc)
    end)
    |> then(fn state ->
      {%{state | events: []}, Enum.reverse(state.events)}
    end)
  end

  @spec send_publish_success(map()) :: {map(), list()}
  def send_publish_success(state) do
    Responses.publish_success(state.publish_msg.stream_key)
    |> send_rtmp_payload(state.socket,
      chunk_stream_id: 3,
      stream_id: state.publish_header.stream_id
    )

    {%{state | events: []}, [{:published, state.publish_msg} | state.events]}
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
    state = get_media_events(header, data, state)
    {:cont, state}
  end

  defp do_handle_client_message(%Messages.AdditionalMedia{} = media, header, state) do
    state = get_additional_media_events(header, media, state)
    {:cont, state}
  end

  defp do_handle_client_message(%Handshake.Step{type: :s0_s1_s2} = step, _header, state) do
    state.socket_module.send(state.socket, Handshake.Step.serialize(step))

    connection_epoch = Handshake.Step.epoch(step)
    {:cont, %{state | epoch: connection_epoch}}
  end

  defp do_handle_client_message(%Messages.SetChunkSize{chunk_size: chunk_size}, _header, state) do
    {:cont, %{state | events: [{:set_chunk_size_required, chunk_size} | state.events]}}
  end

  @stream_begin_type 0
  defp do_handle_client_message(%Messages.Connect{} = connect_msg, _header, state) do
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

    state = %{state | events: [{:connected, connect_msg} | state.events]}
    {:cont, state}
  end

  # According to ffmpeg's documentation, this command should make the server release channel for a media stream
  # We are simply acknowledging the message
  defp do_handle_client_message(%Messages.ReleaseStream{} = release_stream_msg, _header, state) do
    release_stream_msg.tx_id
    |> Responses.default_result([0.0, :null])
    |> send_rtmp_payload(state.socket, chunk_stream_id: 3)

    {:cont, state}
  end

  defp do_handle_client_message(%Messages.Publish{} = publish_msg, %Header{} = header, state) do
    %Messages.UserControl{event_type: @stream_begin_type, data: <<0, 0, 0, 1>>}
    |> send_rtmp_payload(state.socket, chunk_stream_id: 2)

    # at this point pause the unfinished handshake until pipeline demands data from this client
    # (this mechanism prevents accepting streams with no listeners)

    {:halt, %{state | publish_msg: publish_msg, publish_header: header}}
  end

  # A message containing stream metadata
  defp do_handle_client_message(%Messages.SetDataFrame{} = _data_frame, _header, state) do
    {:cont, state}
  end

  defp do_handle_client_message(%Messages.OnMetaData{} = _on_meta_data, _header, state) do
    {:cont, state}
  end

  # According to ffmpeg's documentation, this command should prepare the server to receive media streams
  # We are simply acknowledging the message
  defp do_handle_client_message(%Messages.FCPublish{} = fc_publish, _header, state) do
    %Messages.Anonymous{name: "onFCPublish", tx_id: fc_publish.tx_id, properties: []}
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

  defp do_handle_client_message(%Messages.UserControl{} = msg, _header, state) do
    Logger.warning("Received unsupported user control message of type #{inspect(msg.event_type)}")

    {:cont, state}
  end

  defp do_handle_client_message(%Messages.DeleteStream{}, _header, state) do
    {:halt, %{state | events: [:delete_stream | state.events]}}
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

  defp get_media_events(rtmp_header, data, %{header_sent?: true} = state) do
    payload = get_flv_tag(rtmp_header, data)

    Map.update!(state, :events, &[{:data_available, payload} | &1])
  end

  defp get_media_events(rtmp_header, data, state) do
    payload = get_flv_header() <> get_flv_tag(rtmp_header, data)

    %{
      state
      | header_sent?: true,
        events: [{:data_available, payload} | state.events]
    }
  end

  defp get_additional_media_events(
         %Membrane.RTMP.Header{} = rtmp_header,
         additional_media,
         %{header_sent?: true} = state
       ) do
    # NOTE: we are replacing the type_id from 18 to 8 (script data to audio data) as it carries the
    # additional audio track
    data = additional_media.media

    header = %Membrane.RTMP.Header{
      rtmp_header
      | type_id: 8,
        body_size: byte_size(data)
    }

    # NOTE: for additional media we are also setting the stream_id to 1.
    # It is against the spec but it simplifies things for us since we don't have to
    # handle dynamic pads in the RTMP source + our FLV demuxer handles that well.
    payload = get_flv_tag(header, 1, data)

    event = {:data_available, payload}

    Map.update!(state, :events, &[event | &1])
  end

  defp get_additional_media_events(%Membrane.RTMP.Header{} = rtmp_header, additional_media, state) do
    data = additional_media.media

    header = %Membrane.RTMP.Header{rtmp_header | type_id: 8, body_size: byte_size(data)}
    payload = get_flv_header() <> get_flv_tag(header, 1, data)

    event = {:data_available, payload}

    %{state | header_sent?: true, events: [event | state.event]}
  end

  defp get_flv_header() do
    alias Membrane.FLV

    {header, 0} =
      FLV.Serializer.serialize(
        %FLV.Header{audio_present?: true, video_present?: true},
        0
      )

    # Add PreviousTagSize, which is 0 for the first tag
    header <> <<0::32>>
  end

  # according to the FLV spec, the stream ID should always be 0
  # but we can use 1 for hacking around Twitch's addtional audio stream
  defp get_flv_tag(
         %Membrane.RTMP.Header{
           timestamp: timestamp,
           body_size: data_size,
           type_id: type_id
         },
         stream_id \\ 0,
         payload
       ) do
    tag_size = data_size + 11

    <<upper_timestamp::8, lower_timestamp::24>> = <<timestamp::32>>

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

  @compile {:inline, socket_module: 1}
  defp socket_module(socket) when is_tuple(socket) and elem(socket, 0) == :sslsocket do
    :ssl
  end

  defp socket_module(_socket) do
    :gen_tcp
  end
end
