defmodule Membrane.FLV.Parser do
  def parse(data) do
    case parse_header(data) do
      {:ok, _, _} = return -> return
      _else -> parse_packets(data)
    end
  end

  def parse_header(
        <<"FLV", 0x01::8, 0::5, audio_present?::1, 0::1, video_present?::1, data_offset::32,
          _rest::binary>> = frame
      ) do
    global_header = %{
      audio_present?: flag_to_boolean(audio_present?),
      video_present?: flag_to_boolean(video_present?)
    }

    <<_data::binary-size(data_offset), rest::binary>> = frame

    {:ok, {:header, global_header}, rest}
  end

  def parse_header(_else), do: {:error, :invalid_header}

  def flag_to_boolean(1), do: true
  def flag_to_boolean(0), do: false

  def parse_packets(
        <<_previous_tag_size::32, _reserved::2, 0::1, type::5, data_size::24, timestamp::24,
          timestamp_extended::8, stream_id::24, payload::binary-size(data_size), rest::binary>>
      ) do
    use Bitwise
    {:ok, {:packets, packets}, leftover} = parse_packets(rest)

    packet = %{
      type: resolve_type(type),
      timestamp_extended: (timestamp_extended <<< 24) + timestamp,
      stream_id: stream_id,
      payload: parse_packet_payload(type, payload)
    }

    {:ok, {:packets, [packet | packets]}, leftover}
  end

  def parse_packets(leftover) do
    {:ok, {:packets, []}, leftover}
  end

  defp parse_packet_payload(
         8,
         <<10::4, 3::2, _sound_size::1, 1::1, acc_packet_type::8, data::binary>>
       ) do
    packet_type =
      case acc_packet_type do
        0 -> :aac_audio_specific_config
        1 -> :aac_frame
        2 -> :aac_end_of_sequence
      end

    %{
      codec: :AAC,
      packet_type: packet_type,
      payload: data
    }
  end

  defp parse_packet_payload(8, _else), do: %{packet_type: :audio, payload: :unknown_variation}

  defp parse_packet_payload(
         9,
         <<frame_type::4, 7::4, avc_packet_type::8, composition_time::24, data::binary>>
       ) when frame_type in [1,2,5] do
    packet_type =
      case avc_packet_type do
        0 -> :avc_decoder_configuration_record
        1 -> :avc_frame
        2 -> :avc_end_of_sequence
      end

    %{
      codec: :AVC,
      packet_type: packet_type,
      payload: data,
      composition_time: composition_time
    }
  end

  defp parse_packet_payload(9, _else), do: %{packet_type: :video, payload: :unknown_variation}

  defp parse_packet_payload(18, _whatever),
    do: %{packet_type: :script_data, payload: :unknown_variation}

  defp resolve_type(8), do: :audio
  defp resolve_type(9), do: :video
  defp resolve_type(18), do: :script_data
  defp resolve_type(other), do: {:unknown, other}
end
