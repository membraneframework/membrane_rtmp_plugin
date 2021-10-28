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
    mode: :pull

  def_output_pad :video,
    availability: :always,
    caps: :any,
    mode: :pull

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
                Time the server will wait for connection from the client

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

    with {:ok, native} <- Native.create(state.url, state.timeout) do
      Membrane.Logger.debug("Connection established @ #{state.url}")
      state = Map.put(state, :native, native)
      {{:ok, get_params(native)}, state}
    else
      {:error, reason} ->
        raise("Transition to state `playing` failed. Reason: `#{reason}`")
    end
  end

  @impl true
  def handle_demand(pad, _size, :buffers, _ctx, state) do
    with {:ok, type, frame} <- Native.read_frame(state.native) do
      payload = prepare_payload(type, frame)
      {{:ok, buffer: {type, %Buffer{payload: payload}}, redemand: pad}, state}
    else
      :end_of_stream ->
        {{:ok, end_of_stream: :audio, end_of_stream: :video}, state}

      {:error, reason} ->
        raise("Fetching frame failed. Reason: `#{reason}`")
    end
  end

  defp prepare_payload(:video, payload), do: AVC.Utils.to_annex_b(payload)
  defp prepare_payload(:audio, payload), do: payload

  defp get_params(native),
    do:
      [
        get_audio_params(native),
        get_video_params(native)
      ]
      |> Enum.concat()

  defp get_audio_params(native) do
    with {:ok, asc} <- Native.get_audio_params(native),
         {:ok, caps} <- get_aac_caps(asc) do
      [caps: {:audio, caps}]
    else
      {:error, _reason} -> []
    end
  end

  defp get_video_params(native) do
    with {:ok, config} <- Native.get_video_params(native),
         {:ok, parsed} <- AVC.Configuration.parse(config),
         %AVC.Configuration{pps: [pps], sps: [sps]} = parsed do
      [buffer: {:video, %Buffer{payload: <<0, 0, 1>> <> sps <> <<0, 0, 1>> <> pps}}]
    else
      {:error, _reason} -> []
    end
  end

  defp get_aac_caps(
         <<profile::5, sr_index::4, channel_configuration::4, frame_length_flag::1, _rest::bits>> =
           _audio_specific_config
       ),
       do:
         %AAC{
           profile: AAC.aot_id_to_profile(profile),
           mpeg_version: 4,
           sample_rate: AAC.sampling_frequency_id_to_sample_rate(sr_index),
           channels: AAC.channel_config_id_to_channels(channel_configuration),
           encapsulation: :none,
           samples_per_frame: if(frame_length_flag == 1, do: 1024, else: 960)
         }
         |> then(&{:ok, &1})

  defp get_aac_caps(_otherwise), do: {:error, :unknown_pattern}
end
