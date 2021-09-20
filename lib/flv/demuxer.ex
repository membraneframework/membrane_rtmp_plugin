defmodule Membrane.FLV.Demuxer do
  use Membrane.Filter

  require Membrane.Logger

  alias Membrane.FLV.Parser
  alias Membrane.{Buffer, AAC}

  def_input_pad :input,
    availability: :always,
    demand_unit: :buffers,
    caps: :any

  def_output_pad :audio,
    availability: :always,
    caps: :any,
    mode: :pull

  def_output_pad :video,
    availability: :always,
    caps: :any,
    mode: :pull

  @impl true
  def handle_init(_opts) do
    {:ok, %{partial: <<>>}}
  end

  @impl true
  def handle_demand(_pad, size, :buffers, _ctx, state) do
    demand = size
    {{:ok, demand: {:input, demand}}, state}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: payload}, _ctx, state) do
    case parse(state.partial <> payload) do
      {:error, _reason, leftover} ->
        {{:ok, redemand: :audio}, %{state | partial: leftover}}

      {:ok, packets, leftover} ->
        {{:ok, get_actions(packets)}, %{state | partial: leftover}}
    end
  end

  defp parse(data) do
    case Parser.parse(data) do
      {:ok, {:header, _header}, leftover} -> parse(leftover)
      {:ok, {:packets, packets}, leftover} -> {:ok, packets, leftover}
      {:error, reason} -> {:error, reason, data}
    end
  end

  defp get_actions([]), do: [redemand: :audio]

  defp get_actions(packets) do
    packets
    |> Enum.reject(& &1.payload.payload == :unknown_variation)
    |> Enum.flat_map(fn %{payload: %{payload: payload, packet_type: payload_type}, type: type} ->
      case payload_type do
        :aac_audio_specific_config ->
          [caps: {:audio, get_aac_caps(payload)}]

        :avc_decoder_configuration_record ->
          # [caps: {:video, {:AVC, :decoder_configuration_record, payload}}]
          []

        _else ->
          if type == :video, do: Membrane.Logger.debug("Sending video frame")
          [buffer: {type, %Buffer{payload: payload}}]
      end
    end)
  end

  defp get_aac_caps(<<profile::5, sr_index::4, channel_configuration::4, frame_length_flag::1, _extension_flag::1, _extension_flag3::1>> = _audio_specific_config) do
    %AAC{
      profile: AAC.aot_id_to_profile(profile),
      mpeg_version: 4,
      sample_rate: AAC.sampling_frequency_id_to_sample_rate(sr_index),
      channels: AAC.channel_config_id_to_channels(channel_configuration),
      encapsulation: :NONE,
      samples_per_frame: if(frame_length_flag == 1, do: 1024, else: 960)
    }
  end
end
