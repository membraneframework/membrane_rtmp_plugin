defmodule Membrane.LOAS.Encapsulator do
  def encapsulate(audio_specific_config, au) do
    <<
      # AudioMuxElement - A data element to signal the used multiplex syntax.
      # useSameStreamMux
      0::1,

      # StreamMuxConfig()
      # audioMuxVersion
      0::1,

      # allStreamsSameTimeFraming
      # A data element indicating whether all payloads, which are multiplexed in
      # PayloadMux(), share a common time base.
      1::1,

      # numSubFrames
      # A data element indicating how many PayloadMux() frames are multiplexed
      # (numSubFrames+1). If more than one PayloadMux() frame is multiplexed, all
      # PayloadMux() share a common StreamMuxConfig().The minimum value is 0
      # indicating 1 subframe.
      0::6,

      # numPrograms
      # A data element indicating how many programs are multiplexed (numProgram+1).
      # The minimum value is 0 indicating 1 program.
      0::4,

      # numLayer
      # A data element indicating how many scalable layers are multiplexed (numLayer+1).
      # The minimum value is 0 indicating 1 layer.
      0::3,

      # AudioSpecificConfig()
      audio_specific_config::binary,

      # frame length type
      # A data element indicating the frame length type of the payload
      # Value 0 means Payload with variable frame length
      0b000::3,

      # latmBufferFullness
      # A data element indicating the state of the bit reservoir in the course of
      # encoding the first access unit of a particular program and layer in an
      # AudioMuxElement(). This value value is frequently ignored by decoders so by
      # default 0xFF, variable bit rate, is given which also means that buffer fullness
      # is not applicable
      0xFF::8,

      # otherDataPresent
      # A flag indicating the presence of the other data than audio payloads.
      # Value 0 means The other data than audio payload otherData is not multiplexed
      0::1,

      # crcCheckPresent
      # A data element indicating the presence of CRC check bits for the
      # StreamMuxConfig() data functions.
      # Value 0 means CRC check bits are not present
      0::1,
      payload_length_info(byte_size(au))::binary,
      au::binary
    >>
    |> byte_alignment()
    |> append_audio_sync_stream()
  end

  defp payload_length_info(size) when size >= 255 do
    <<255::8>> <> payload_length_info(size - 255)
  end

  defp payload_length_info(size) do
    <<size::8>>
  end

  defp append_audio_sync_stream(data) do
    len = byte_size(data)

    <<
      # syncword
      0x2B7::11,
      len::13
    >> <> data
  end

  defp byte_alignment(data) when is_binary(data), do: data
  defp byte_alignment(data), do: <<data::bitstring, 0::1>> |> byte_alignment()
end
