defmodule Membrane.RTMP.Source do
  @moduledoc """
  Membrane Element being a server-side source of RTMP streams.

  Implementation based on FFmpeg
  """
  use Membrane.Source
  alias __MODULE__.Native
  alias Membrane.{AVC, Time, AAC, Buffer}
  require Membrane.Logger

  def_output_pad :audio,
    availability: :always,
    caps: {AAC, encapsulation: :none},
    mode: :push

  def_output_pad :video,
    availability: :always,
    caps: :any,
    mode: :push

  def_options url: [
                spec: binary(),
                description: """
                URL on which the FFmpeg instance will be created
                """
              ],
              timeout: [
                spec: Time.t() | :infinity,
                default: :infinity,
                description: """
                Time during which the connection with the client must be established before handle_prepared_to_playing fails.

                Duration given must be a multiply of one second or atom `:infinity`.
                """
              ]

  @impl true
  def handle_init(%__MODULE__{} = opts) do
    {:ok, Map.from_struct(opts) |> Map.merge(%{native: nil})}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    # Native.create is blocking. Hence, the element will only go from prepared to playing when a new connection is established.
    # This might not be desirable, but unfortunately this is caused by the fact that FFmpeg's create_input_stream is awaiting a new connection from the client before returning.

    with {:ok, native} <- Native.create(state.url, state.timeout),
         :ok <- Native.stream_frames(native) do
      Membrane.Logger.debug("Connection established @ #{state.url}")
      {:ok, %{state | native: native}}
    else
      {:error, reason} ->
        raise("Transition to state `playing` failed. Reason: `#{reason}`")
    end
  end

  @impl true
  def handle_playing_to_prepared(_ctx, state) do
    if not is_nil(state.native), do: Native.stop_streaming(state.native)
    {:ok, %{state | native: nil}}
  end

  @impl true
  def handle_other(:end_of_stream, _ctx, state) do
    {{:ok, end_of_stream: :audio, end_of_stream: :video}, state}
  end

  def handle_other({:video_params, config}, _ctx, state) do
    %{pps: [pps], sps: [sps]} = Membrane.AVC.Configuration.parse(config)
    payload = <<0, 0, 1>> <> sps <> <<0, 0, 1>> <> pps
    {{:ok, buffer: {:video, %Buffer{payload: payload}}}, state}
  end

  def handle_other({:audio_params, asc}, _ctx, state) do
    caps = get_aac_caps(asc)
    {{:ok, caps: {:audio, caps}}, state}
  end

  def handle_other({:audio, audio}, _ctx, state) do
    {{:ok, buffer: {:audio, %Buffer{payload: audio}}}, state}
  end

  def handle_other({:video, payload}, _ctx, state) do
    {{:ok, buffer: {:video, %Buffer{payload: AVC.Utils.to_annex_b(payload)}}}, state}
  end

  def handle_other(msg, _ctx, _state) do
    raise("Unhandled message #{inspect(msg)}")
  end

  defp get_aac_caps(
         <<profile::5, sr_index::4, channel_configuration::4, frame_length_flag::1, _rest::bits>> =
           _audio_specific_config
       ),
       do: %AAC{
         profile: AAC.aot_id_to_profile(profile),
         mpeg_version: 4,
         sample_rate: AAC.sampling_frequency_id_to_sample_rate(sr_index),
         channels: AAC.channel_config_id_to_channels(channel_configuration),
         encapsulation: :none,
         samples_per_frame: if(frame_length_flag == 1, do: 1024, else: 960)
       }
end
