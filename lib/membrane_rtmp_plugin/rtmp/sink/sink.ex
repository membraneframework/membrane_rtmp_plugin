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
  alias Membrane.{AAC, MP4, Buffer}

  @supported_protocols ["rtmp://", "rtmps://"]
  @connection_attempt_interval 500
  @default_state %{
    attempts: 0,
    native: nil,
    # Keys here are the pad names.
    frame_buffer: %{audio: nil, video: nil},
    ready: false,
    forward_mode: false
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
  def handle_write(pad, buffer, _ctx, %{forward_mode: true} = state) do
    case write_frame(state, pad, buffer) do
      {:ok, state} -> {{:ok, demand: pad}, state}
      {:error, reason} -> {:error, reason}
    end
  end

  def handle_write(pad, buffer, _ctx, %{ready: false} = state) do
    fill_frame_buffer(state, pad, buffer)
  end

  def handle_write(pad, buffer, _ctx, state) do
    case fill_frame_buffer(state, pad, buffer) do
      {:ok, state} -> write_frame_interleaved(state)
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def handle_end_of_stream(pad, ctx, state) do
    if ctx.pads |> Map.values() |> Enum.all?(& &1.end_of_stream?) do
      Native.finalize_stream(state.native)
      {:ok, state}
    else
      # The interleave logic does not work if either one of the inputs does not
      # produce buffers. From this point on we act as a "forward" filter.
      other_pad =
        case pad do
          :audio -> :video
          :video -> :audio
        end

      case flush_frame_buffer(state) do
        {:ok, state} ->
          {{:ok, demand: other_pad}, %{state | forward_mode: true}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  def handle_other(:try_connect, _ctx, %{attempts: attempts, max_attempts: max_attempts} = state)
      when max_attempts != :infinity and attempts >= max_attempts do
    {:error, "failed to connect to '#{state.rtmp_url}' #{attempts} times, aborting"}
  end

  def handle_other(:try_connect, _ctx, state) do
    state = %{state | attempts: state.attempts + 1}

    case Native.try_connect(state.native) do
      :ok ->
        Membrane.Logger.debug("Correctly initialized connection with: #{state.rtmp_url}")

        {{:ok, [{:playback_change, :resume} | build_demand(state)]}, state}

      {:error, error} when error in [:econnrefused, :etimedout] ->
        Process.send_after(self(), :try_connect, @connection_attempt_interval)

        Membrane.Logger.warn(
          "Connection to #{state.rtmp_url} refused, retrying in #{@connection_attempt_interval}ms"
        )

        {:ok, state}

      {:error, reason} ->
        {:error, "Failed to connect to '#{state.rtmp_url}': #{reason}"}
    end
  end

  defp build_demand(%{frame_buffer: fb}) do
    fb
    |> Enum.filter(fn {_pad, buffer} -> buffer == nil end)
    |> Enum.map(fn {pad, _} -> {:demand, pad} end)
  end

  defp fill_frame_buffer(state, pad, buffer) do
    if get_in(state, [:frame_buffer, pad]) != nil do
      {:error, "attempted to overwrite frame buffer on pad #{inspect(pad)}"}
    else
      {:ok, put_in(state, [:frame_buffer, pad], buffer)}
    end
  end

  defp write_frame_interleaved(state = %{frame_buffer: fb = %{audio: audio, video: video}}) do
    ready? = audio != nil and video != nil

    if ready? do
      {pad, buffer} =
        Enum.min_by(fb, fn {_, buffer} ->
          Buffer.get_dts_or_pts(buffer)
        end)

      case write_frame(state, pad, buffer) do
        {:ok, state} ->
          state = put_in(state, [:frame_buffer, pad], nil)
          {{:ok, build_demand(state)}, state}

        {:error, reason} ->
          {:error, reason}
      end
    else
      # We still have to wait for the other frame.
      {:ok, state}
    end
  end

  defp flush_frame_buffer(state = %{frame_buffer: fb}) do
    pads_with_buffer =
      fb
      |> Enum.filter(fn {_pad, buffer} -> buffer != nil end)
      |> Enum.sort(fn {_, left}, {_, right} ->
        Buffer.get_dts_or_pts(left) <= Buffer.get_dts_or_pts(right)
      end)

    Enum.reduce(pads_with_buffer, {:ok, state}, fn
      {pad, buffer}, {:ok, state} ->
        case write_frame(state, pad, buffer) do
          {:ok, state} -> {:ok, put_in(state, [:frame_buffer, pad], nil)}
          {:error, reason} -> {:error, reason}
        end

      {_pad, _buffer}, {:error, reason} ->
        {:error, reason}
    end)
  end

  defp write_frame(state, :audio, buffer) do
    buffer_pts = buffer.pts |> Ratio.ceil()

    case Native.write_audio_frame(state.native, buffer.payload, buffer_pts) do
      {:ok, native} ->
        {:ok, Map.put(state, :native, native)}

      {:error, reason} ->
        {:error, "writing audio frame failed with reason: #{inspect(reason)}"}
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
        {:ok, Map.put(state, :native, native)}

      {:error, reason} ->
        {:error, "writing video frame failed with reason: #{inspect(reason)}"}
    end
  end
end
