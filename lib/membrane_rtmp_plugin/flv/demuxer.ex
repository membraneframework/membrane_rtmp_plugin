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
    mode: :pull,
    demand_unit: :buffers

  def_output_pad :audio,
    availability: :always,
    caps: {AAC, encapsulation: :none},
    mode: :pull

  def_output_pad :video,
    availability: :always,
    caps: :any,
    mode: :pull

  def_options output_avc_configuration: [
                spec: boolean(),
                default: true,
                description: """
                Flag defining whether to output the PPS and SPS from the demuxer
                """
              ]

  @impl true
  def handle_init(%__MODULE__{} = opts) do
    {:ok, Map.from_struct(opts) |> Map.merge(%{partial: <<>>})}
  end

  @impl true
  def handle_demand(_pad, size, :buffers, _ctx, state) do
    {{:ok, demand: {:input, size}}, state}
  end

  @impl true
  def handle_process(:input, %Buffer{payload: payload}, _ctx, state) do
    {:ok, packets, leftover} = parse(state.partial <> payload)
    {{:ok, get_actions(packets, state) ++ [redemand: :video]}, %{state | partial: leftover}}
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

  defp get_actions([], _state), do: []

  defp get_actions(packets, state) do
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

        :avc_decoder_configuration_record when state.output_avc_configuration ->
          %{pps: [pps], sps: [sps]} = Membrane.AVC.Configuration.parse(payload)

          [
            buffer:
              {:video,
               %Buffer{
                 metadata: %{timestamp: timestamp},
                 payload: <<0, 0, 1>> <> sps <> <<0, 0, 1>> <> pps
               }}
          ]

        :aac_frame ->
          [buffer: {:audio, %Buffer{metadata: %{timestamp: timestamp}, payload: payload}}]

        :avc_frame ->
          [buffer: {:video, %Buffer{metadata: %{timestamp: timestamp}, payload: payload}}]

        _other ->
          []
      end
    end)
  end

  @spec get_aac_caps(binary()) :: AAC.t()
  def get_aac_caps(
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
