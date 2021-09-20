alias Membrane.LOAS.Encapsulator

data = File.read!("output.flv")
{_headers, packets, leftover} = Membrane.RTMP.FLV.Parser.parse_frames(data)
IO.puts("Size of the leftover is #{byte_size(leftover)} bytes")
<<_head::binary-size(5), expected_size::24, rest::binary>> = leftover
IO.puts("Size of the leftover should have been #{expected_size} bytes")

[%{payload: %{payload: asc}}] =
  Enum.filter(packets, fn %{payload: %{packet_type: type}} ->
    type == :aac_audio_specific_config
  end)

audio_frames =
  Enum.filter(packets, fn %{payload: %{packet_type: type}} -> type == :aac_frame end)
  |> Enum.map(& &1.payload.payload)
  |> Enum.map(&Encapsulator.encapsulate(asc, &1))

Enum.each(audio_frames, &File.write!("output.aac", &1, [:binary, :append]))
