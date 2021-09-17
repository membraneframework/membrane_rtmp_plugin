defmodule Membrane.RTMP.FLV.Parser do

  def parse_frames(<<"FLV", 0x01::8, 0::5, audio_present?::1, 0::1, video_present?::1, data_offset::32, _rest::binary>> = frame) do
    global_header = %{
      audio_present?: flag_to_boolean(audio_present?),
      video_present?: flag_to_boolean(video_present?),
    }

    <<_data::binary-size(data_offset), rest::binary>> = frame

    {packets, leftover} = parse_packets(rest)

    {global_header, packets, leftover}
  end

  def flag_to_boolean(1), do: true
  def flag_to_boolean(0), do: false

  def parse_packets(<<_previous_tag_size::32, _reserved::2, 0::1, type::5, data_size::24, timestamp::24, timestamp_extended::8, stream_id::24, payload::binary-size(data_size), rest::binary>>) do
    use Bitwise
    IO.puts("A taka dupa")
    {rest, leftover} = parse_packets(rest)
    {[%{
      type: type,
      timestamp_extended: (timestamp_extended <<< 24) + timestamp,
      stream_id: stream_id,
      payload: parse_packet_payload(type, payload),
    } | rest], leftover}
  end
  def parse_packets(leftover) do
    IO.puts("A koniec tego")
    {[], leftover}
  end

  defp parse_packet_payload(8, <<10::4, 3::2, _sound_size::1, 1::1, acc_packet_type::8, data::binary>>) do
    packet_type =
      case acc_packet_type do
        0 -> :aac_audio_specific_config
        1 -> :aac_frame
      end

    %{
      codec: :AAC,
      packet_type: packet_type,
      payload: data
    }
  end
  defp parse_packet_payload(8, _else), do: %{packet_type: :audio, payload: :unknown_variation}

  defp parse_packet_payload(9, <<frame_type::4, 7::4, avc_packet_type::8, composition_time::24, data::binary>>) do
    packet_type =
      case avc_packet_type do
        0 -> :avc_decoder_configuration_record
        1 -> :avc_frame
      end

    %{
      codec: :AVC,
      packet_type: packet_type,
      payload: data,
      composition_time: composition_time
    }
  end
  defp parse_packet_payload(9, _else), do: %{packet_type: :video, payload: :unknown_variation}

  defp parse_packet_payload(18, _whatever), do: %{packet_type: :script_data, payload: :unsupported}
end
