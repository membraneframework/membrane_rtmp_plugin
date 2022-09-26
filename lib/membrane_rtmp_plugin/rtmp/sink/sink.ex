defmodule Membrane.RTMP.Sink do
  @moduledoc """
  Membrane element being client-side of RTMP streams.
  To work successfuly it requires to receive both audio and video streams in AAC and H264 format respectively. Currently it supports only:
    - RTMP proper - "plain" RTMP protocol
    - RTMPS - RTMP over TLS/SSL
  other RTMP veriants - RTMPT, RTMPE, RTMFP are not supported.
  Implementation based on FFmpeg.
  """
  use Membrane.Sink

  require Membrane.Logger

  alias __MODULE__.Native
  alias Membrane.{AAC, MP4}

  @supported_protocols ["rtmp://", "rtmps://"]
  @connection_attempt_interval 500
  @default_state %{
    attempts: 0,
    native: nil,
    buffered_frame: nil,
    ready: false,
    current_timestamps: %{}
  }

  def_input_pad :audio,
    availability: :always,
    caps: AAC,
    mode: :pull,
    demand_unit: :buffers

  def_input_pad :video,
    availability: :always,
    caps: MP4.Payload,
    mode: :pull,
    demand_unit: :buffers

  def_options rtmp_url: [
                type: :string,
                spec: String.t(),
                description:
                  "Destination URL of the stream. It needs to start with rtmp:// or rtmps:// depending on the protocol variant.
                This URL should be provided by your streaming service."
              ],
              max_attempts: [
                spec: pos_integer() | :infinity,
                default: 1,
                description: """
                Maximum number of connection attempts before failing with an error.
                The attempts will happen every #{@connection_attempt_interval} ms
                """
              ]

  @impl true
  def handle_init(options) do
    unless String.starts_with?(options.rtmp_url, @supported_protocols) do
      raise ArgumentError, "Invalid destination URL provided"
    end

    unless options.max_attempts == :infinity or
             (is_integer(options.max_attempts) and options.max_attempts >= 1) do
      raise ArgumentError, "Invalid max_attempts option value: #{options.max_attempts}"
    end

    {:ok, options |> Map.from_struct() |> Map.merge(@default_state)}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    {:ok, native} = Native.create(state.rtmp_url)
    send(self(), :try_connect)

    {{:ok, playback_change: :suspend}, %{state | native: native}}
  end

  @impl true
  def handle_playing_to_prepared(_ctx, state) do
    state = Map.merge(state, @default_state)
    Membrane.Logger.debug("Stream correctly closed")
    {:ok, state}
  end

  @impl true
  def handle_caps(
        :video,
        %MP4.Payload{content: %MP4.Payload.AVC1{avcc: avc_config}} = caps,
        _ctx,
        state
      ) do
    case Native.init_video_stream(state.native, caps.width, caps.height, avc_config) do
      {:ok, ready, native} ->
        Membrane.Logger.debug("Correctly initialized video stream.")
        state = Map.merge(state, %{native: native, ready: ready})
        {:ok, state}

      {:error, :caps_resent} ->
        Membrane.Logger.error(
          "Input caps redefined on pad :video. RTMP Sink does not support changing stream parameters"
        )

        {:ok, state}
    end
  end

  @impl true
  def handle_caps(:audio, %Membrane.AAC{} = caps, _ctx, state) do
    profile = AAC.profile_to_aot_id(caps.profile)
    sr_index = AAC.sample_rate_to_sampling_frequency_id(caps.sample_rate)
    channel_configuration = AAC.channels_to_channel_config_id(caps.channels)
    frame_length_id = AAC.samples_per_frame_to_frame_length_id(caps.samples_per_frame)

    aac_config =
      <<profile::5, sr_index::4, channel_configuration::4, frame_length_id::1, 0::1, 0::1>>

    case Native.init_audio_stream(state.native, caps.channels, caps.sample_rate, aac_config) do
      {:ok, ready, native} ->
        Membrane.Logger.debug("Correctly initialized audio stream.")
        state = Map.merge(state, %{native: native, ready: ready})
        {:ok, state}

      {:error, :caps_resent} ->
        Membrane.Logger.error(
          "Input caps redefined on pas :audio. RTMP Sink does not support changing stream paremeters"
        )

        {:ok, state}
    end
  end

  @impl true
  def handle_write(pad, buffer, _ctx, %{ready: false} = state) do
    state = Map.put(state, :buffered_frame, {pad, buffer})
    {:ok, state}
  end

  @impl true
  def handle_write(
        pad,
        buffer,
        _ctx,
        %{ready: true, buffered_frame: {frame_pad, frame}} = state
      ) do
    state = write_frame(state, frame_pad, frame) |> write_frame(pad, buffer)
    {{:ok, demand: get_demand(state)}, Map.put(state, :buffered_frame, nil)}
  end

  @impl true
  def handle_write(pad, buffer, _ctx, state) do
    state = write_frame(state, pad, buffer)
    {{:ok, demand: get_demand(state)}, state}
  end

  @impl true
  def handle_end_of_stream(pad, ctx, state) do
    if ctx.pads |> Map.values() |> Enum.all?(& &1.end_of_stream?) do
      Native.finalize_stream(state.native)
      {:ok, state}
    else
      state = Map.update!(state, :current_timestamps, &Map.delete(&1, pad))
      {{:ok, demand: get_demand(state)}, state}
    end
  end

  @impl true
  def handle_other(:try_connect, _ctx, %{attempts: attempts, max_attempts: max_attempts} = state)
      when max_attempts != :infinity and attempts >= max_attempts do
    raise "Failed to connect to '#{state.rtmp_url}' #{attempts} times, aborting"
  end

  def handle_other(:try_connect, ctx, state) do
    state = %{state | attempts: state.attempts + 1}

    case Native.try_connect(state.native) do
      :ok ->
        Membrane.Logger.debug("Correctly initialized connection with: #{state.rtmp_url}")
        demands = ctx.pads |> Map.keys() |> Enum.map(&{:demand, &1})
        {{:ok, [{:playback_change, :resume} | demands]}, state}

      {:error, error} when error in [:econnrefused, :etimedout] ->
        Process.send_after(self(), :try_connect, @connection_attempt_interval)

        Membrane.Logger.warn(
          "Connection to #{state.rtmp_url} refused, retrying in #{@connection_attempt_interval}ms"
        )

        {:ok, state}

      {:error, reason} ->
        raise "Failed to connect to '#{state.rtmp_url}': #{reason}"
    end
  end

  defp write_frame(state, :audio, buffer) do
    buffer_pts = buffer.pts |> Ratio.ceil()

    case Native.write_audio_frame(state.native, buffer.payload, buffer_pts) do
      {:ok, native} ->
        Map.put(state, :native, native)
        |> Map.update!(:current_timestamps, fn curr_tmps ->
          Map.put(curr_tmps, :audio, buffer_pts)
        end)

      {:error, reason} ->
        raise("Writing audio frame failed with reason: #{reason}")
    end
  end

  defp write_frame(state, :video, buffer) do
    case Native.write_video_frame(
           state.native,
           buffer.payload,
           buffer.dts,
           buffer.metadata.h264.key_frame?
         ) do
      {:ok, native} ->
        Map.put(state, :native, native)
        |> Map.update!(:current_timestamps, fn curr_tmps ->
          Map.put(curr_tmps, :video, buffer.dts)
        end)

      {:error, reason} ->
        raise("Writing video frame failed with reason: #{reason}")
    end
  end

  defp get_demand(state) do
    {pad, _timestamp} =
      state.current_timestamps |> Enum.min_by(fn {_pad, timestamp} -> timestamp end)

    {pad, 1}
  end
end
