defmodule Membrane.RTMP.Sink do
  @moduledoc """
  Membrane element being client-side of RTMP streams

  Implementation based on FFmpeg.
  Its state machine works as follows:
  1. Wait for H264 and AAC caps to initialize AAC stream paremeters and basic H264 stream parameters
  2. Once both caps have been received, demand first video keyframe to initialize AVC decoder configuration and write stream
  header to the destination.
  3. Once first video frame has been received and header has been succesfully written, demand input from both audio and video
  input pads.
  """
  use Membrane.Sink
  alias __MODULE__.Native
  alias Membrane.{AAC}
  require Membrane.Logger

  def_input_pad :audio,
    availability: :always,
    caps: AAC,
    mode: :pull,
    demand_unit: :buffers

  def_input_pad :video,
    availability: :always,
    caps: :any,
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
  def handle_caps(:video, %Membrane.Caps.Video.H264{} = caps, _ctx, state) do
    {frames, seconds} = caps.framerate

    case Native.init_video_stream(state.native_state, caps.width, caps.height, frames, seconds) do
      {:ok, ready, native_state} ->
        Membrane.Logger.debug("Correctly initialized video stream.")
        state = Map.put(state, :native_state, native_state)

        case ready do
          true ->
            {{:ok, demand: :video}, state}

          _ ->
            {:ok, state}
        end

      {:error, reason} ->
        raise("#{reason}")
    end
  end

  @impl true
  def handle_caps(:audio, %Membrane.AAC{} = caps, _ctx, state) do
    aac_config = get_aac_config(caps)

    case Native.init_audio_stream(state.native_state, caps.channels, caps.sample_rate, aac_config) do
      {:ok, ready, native_state} ->
        Membrane.Logger.debug("Correctly initialized audio stream.")
        state = Map.put(state, :native_state, native_state)

        case ready do
          true ->
            {{:ok, demand: :video}, state}

          _ ->
            {:ok, state}
        end

      {:error, reason} ->
        raise("#{reason}")
    end
  end

  @impl true
  def handle_write(
        :video,
        %Membrane.Buffer{metadata: %{h264: %{key_frame?: true, nalus: nalus}}} = buffer,
        ctx,
        state
      ) do
    {sps_start, sps_len} =
      nalus
      |> Enum.filter(fn el -> el.metadata.h264.type == :sps end)
      |> List.first()
      |> Map.get(:unprefixed_poslen)

    {pps_start, pps_len} =
      nalus
      |> Enum.filter(fn el -> el.metadata.h264.type == :pps end)
      |> List.first()
      |> Map.get(:unprefixed_poslen)

    <<_head::binary-size(sps_start), sps::binary-size(sps_len), _tail::bitstring>> =
      buffer.payload

    <<_head::binary-size(pps_start), pps::binary-size(pps_len), _tail::bitstring>> =
      buffer.payload

    <<_sps_header::8, profile_idc::8, constraints::8, level_idc::8, _sps_tail::bitstring>> = sps

    avc_configuration_record =
      <<1::8, profile_idc::8, constraints::8, level_idc::8, 0b111111::6, 3::2, 0b111::3, 1::5,
        sps_len::16, sps::binary, 1::8, pps_len::16, pps::binary>>

    case Native.write_header(state.native_state, avc_configuration_record) do
      {:ok, native_state} ->
        state = Map.put(state, :native_state, native_state)
        {:ok, state} = write_video_frame(buffer, state)
        demands = ctx.pads |> Map.keys() |> Enum.map(&{:demand, &1})
        {{:ok, demands}, state}

      {:error, reason} ->
        raise("#{reason}")
    end
  end

  @impl true
  def handle_write(:video, buffer, _ctx, state) do
    {:ok, state} = write_video_frame(buffer, state)
    {{:ok, demand: :video}, state}
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

  defp write_video_frame(buffer, state) do
    case Native.write_video_frame(
           state.native_state,
           buffer.payload,
           buffer.dts,
           buffer.metadata.h264.key_frame?
         ) do
      {:ok, native_state} ->
        state = Map.put(state, :native_state, native_state)
        {:ok, state}

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
