defmodule Membrane.FLV.Demuxer do
  @moduledoc """
  Element for demuxing FLV streams into audio and video streams
  """
  use Membrane.Filter

  alias Membrane.FLV.Parser
  alias Membrane.{Buffer, AAC, FLV, Time}

  require Membrane.Logger

  def_input_pad :input,
    availability: :always,
    caps: {FLV, mode: :packets},
    mode: :push

  def_output_pad :audio,
    availability: :always,
    caps: {AAC, encapsulation: :none},
    mode: :push

  def_output_pad :video,
    availability: :always,
    caps: :any,
    mode: :push

  @impl true
  def handle_init(_opts) do
    {:ok, %{partial: <<>>}}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: payload}, _ctx, state) do
    {:ok, packets, leftover} = parse(state.partial <> payload)
    {{:ok, get_actions(packets)}, %{state | partial: leftover}}
  end

  defp parse(data) do
    case Parser.parse(data) do
      {:ok, {:header, header}, leftover} ->
        Membrane.Logger.debug("Received header #{inspect(header)}. Ignoring")
        parse(leftover)

      {:ok, {:packets, packets}, leftover} ->
        {:ok, packets, leftover}
    end
  end

  defp get_actions([]), do: []

  defp get_actions(packets) do
    packets
    |> Enum.reject(&(&1.payload.payload == :unknown_variation))
    |> Enum.flat_map(fn %{
                          payload: %{payload: payload, packet_type: payload_type},
                          timestamp: timestamp
                        } ->
      timestamp = Time.milliseconds(timestamp)

      case payload_type do
        :aac_audio_specific_config ->
          [caps: {:audio, get_aac_caps(payload)}]

        :aac_frame ->
          [buffer: {:audio, %Buffer{metadata: %{timestamp: timestamp}, payload: payload}}]

        :avc_frame ->
          [buffer: {:video, %Buffer{metadata: %{timestamp: timestamp}, payload: payload}}]

        :avc_end_of_sequence ->
          [end_of_stream: :video]

        :aac_end_of_sequence ->
          [end_of_stream: :audio]

        _other ->
          []
      end
    end)
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    {{:ok, end_of_stream: :audio, end_of_stream: :video}, state}
  end

  defp get_aac_caps(
         <<profile::5, sr_index::4, channel_configuration::4, frame_length_flag::1,
           _extension_flag::1, _extension_flag3::1>> = _audio_specific_config
       ) do
    %AAC{
      profile: AAC.aot_id_to_profile(profile),
      mpeg_version: 4,
      sample_rate: AAC.sampling_frequency_id_to_sample_rate(sr_index),
      channels: AAC.channel_config_id_to_channels(channel_configuration),
      encapsulation: :none,
      samples_per_frame: if(frame_length_flag == 1, do: 1024, else: 960)
    }
  end
end
