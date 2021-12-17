defmodule Membrane.RTMP.Sink do
  @moduledoc """
  Membrane element being client-side of RTMP streams

  Implementation based on FFmpeg.
  """
  use Membrane.Sink
  alias __MODULE__.Native
  alias Membrane.{AAC, MP4}
  require Membrane.Logger

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
                This URL should be provided to you by your streaming service."
              ]

  @impl true
  def handle_init(options) do
    case options.rtmp_url do
      "rtmp://" <> _ -> {:ok, Map.from_struct(options)}
      "rtmps://" <> _ -> {:ok, Map.from_struct(options)}
      _url -> raise("Invalid destination URL provided")
    end
  end

  @impl true
  def handle_prepared_to_playing(ctx, state) do
    case Native.create(state.rtmp_url) do
      {:ok, native} ->
        Membrane.Logger.debug("Correctly initialized connection with: #{state.rtmp_url}")
        state = Map.put(state, :native, native)
        demands = ctx.pads |> Map.keys() |> Enum.map(&{:demand, &1})
        {{:ok, demands}, state}

      {:error, reason} ->
        raise("Transition to state playing failed with reason: #{reason}")
    end
  end

  @impl true
  def handle_playing_to_prepared(_ctx, state) do
    state = Map.drop(state, [:native, :ready, :buffered_frames])
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

      {:error, reason} ->
        raise("Video stream initialization failed with reason: #{reason}")
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

      {:error, reason} ->
        raise("Audio stream initialization failed with reason: #{reason}")
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
        ctx,
        %{ready: true, buffered_frame: {frame_pad, frame}} = state
      ) do
    {_, state} = handle_write(frame_pad, frame, ctx, Map.delete(state, :buffered_frame))
    {_, state} = handle_write(pad, buffer, ctx, state)
    {{:ok, demand: state.current_timestamps |> Enum.min_by(&elem(&1, 1)) |> elem(0)}, state}
  end

  @impl true
  def handle_write(:video, buffer, _ctx, %{ready: true} = state) do
    case Native.write_video_frame(
           state.native,
           buffer.payload,
           buffer.dts,
           buffer.metadata.h264.key_frame?
         ) do
      {:ok, native} ->
        state = Map.put(state, :native, native)

        state =
          Map.update(state, :current_timestamps, %{video: buffer.dts}, fn curr_tmps ->
            Map.put(curr_tmps, :video, buffer.dts)
          end)

        {{:ok, demand: state.current_timestamps |> Enum.min_by(&elem(&1, 1)) |> elem(0)}, state}

      {:error, reason} ->
        raise("Writing video frame failed with reason: #{reason}")
    end
  end

  @impl true
  def handle_write(:audio, buffer, _ctx, %{ready: true} = state) do
    buffer_pts = buffer.pts |> Ratio.ceil()

    case Native.write_audio_frame(state.native, buffer.payload, buffer_pts) do
      {:ok, native} ->
        state = Map.put(state, :native, native)

        state =
          Map.update(state, :current_timestamps, %{audio: buffer_pts}, fn curr_tmps ->
            Map.put(curr_tmps, :audio, buffer_pts)
          end)

        {{:ok, demand: state.current_timestamps |> Enum.min_by(&elem(&1, 1)) |> elem(0)}, state}

      {:error, reason} ->
        raise("Writing audio frame failed with reason: #{reason}")
    end
  end

  @impl true
  def handle_end_of_stream(
        pad,
        _ctx,
        %{current_timestamps: %{audio: _audio_dts, video: _video_dts} = curr_tmps} = state
      ) do
    curr_tmps = Map.delete(curr_tmps, pad)

    {{:ok, demand: curr_tmps |> Map.keys() |> List.first()},
     Map.put(state, :current_timestamps, curr_tmps)}
  end

  @impl true
  def handle_end_of_stream(_pad, _ctx, state) do
    {:ok, Map.delete(state, :current_timestamps)}
  end
end
