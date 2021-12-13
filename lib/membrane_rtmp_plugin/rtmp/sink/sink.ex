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
                description: "URL address of an RTMP/RTMPS stream destination (e.g. youtube)."
              ]

  @impl true
  def handle_init(options) do
    {:ok, Map.from_struct(options)}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    case Native.init_connection(state.rtmp_url) do
      {:ok, native_state} ->
        Membrane.Logger.debug("Correctly initialized connection with: #{state.rtmp_url}")
        state = Map.put(state, :native_state, native_state)
        {:ok, state}

      {:error, reason} ->
        raise("#{reason}")
    end
  end

  @impl true
  def handle_playing_to_prepared(_ctx, state) do
    Native.close_connection(state.native_state)
    state = Map.delete(state, :native_state)
    {:ok, state}
  end

  @impl true
  def handle_caps(:video, %MP4.Payload{} = caps, ctx, state) do
    case Native.init_video_stream(state.native_state, caps.width, caps.height, caps.content.avcc) do
      {:ok, ready, native_state} ->
        Membrane.Logger.debug("Correctly initialized video stream.")
        state = Map.put(state, :native_state, native_state)

        if ready do
          write_header(ctx, state)
        else
          {:ok, state}
        end

      {:error, reason} ->
        raise("#{reason}")
    end
  end

  @impl true
  def handle_caps(:audio, %Membrane.AAC{} = caps, ctx, state) do
    aac_config = get_aac_config(caps)

    case Native.init_audio_stream(state.native_state, caps.channels, caps.sample_rate, aac_config) do
      {:ok, ready, native_state} ->
        Membrane.Logger.debug("Correctly initialized audio stream.")
        state = Map.put(state, :native_state, native_state)

        if ready do
          write_header(ctx, state)
        else
          {:ok, state}
        end

      {:error, reason} ->
        raise("#{reason}")
    end
  end

  @impl true
  def handle_write(:video, buffer, _ctx, state) do
    case Native.write_video_frame(
           state.native_state,
           buffer.payload,
           buffer.dts,
           buffer.metadata.h264.key_frame?
         ) do
      {:ok, native_state} ->
        state = Map.put(state, :native_state, native_state)
        {{:ok, demand: :video}, state}

      {:error, reason} ->
        raise("#{reason}")
    end
  end

  @impl true
  def handle_write(:audio, buffer, _ctx, state) do
    case Native.write_audio_frame(state.native_state, buffer.payload, buffer.pts |> Ratio.ceil()) do
      {:ok, native_state} ->
        state = Map.put(state, :native_state, native_state)
        {{:ok, demand: :audio}, state}

      {:error, reason} ->
        raise("#{reason}")
    end
  end

  defp write_header(ctx, state) do
    case Native.write_header(state.native_state) do
      {:ok, native_state} ->
        state = Map.put(state, :native_state, native_state)
        demands = ctx.pads |> Map.keys() |> Enum.map(&{:demand, &1})
        {{:ok, demands}, state}

      {:error, reason} ->
        raise("#{reason}")
    end
  end

  defp get_aac_config(%Membrane.AAC{} = caps) do
    profile = AAC.profile_to_aot_id(caps.profile)
    sr_index = AAC.sample_rate_to_sampling_frequency_id(caps.sample_rate)
    channel_configuration = AAC.channels_to_channel_config_id(caps.channels)
    frame_length_id = AAC.samples_per_frame_to_frame_length_id(caps.samples_per_frame)

    <<profile::5, sr_index::4, channel_configuration::4, frame_length_id::1, 0::2>>
  end
end
