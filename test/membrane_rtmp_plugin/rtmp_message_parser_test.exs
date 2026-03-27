defmodule Membrane.RTMP.MessageParserTest do
  use ExUnit.Case, async: true

  alias Membrane.RTMP.{Handshake, MessageParser}

  @fixture "test/fixtures/rtmp/blackmagic_4k_live.chunks.bin"

  test "consumes a real 4K Blackmagic RTMP capture without leftover buffered data" do
    parser =
      MessageParser.init(Handshake.init_server())
      |> Map.merge(%{state_machine: :connecting, handshake: nil})

    {message_count, parser} =
      @fixture
      |> File.read!()
      |> decode_chunks()
      |> Enum.reduce({0, parser}, fn chunk, {count, parser} ->
        {messages, parser} = MessageParser.parse_packet_messages(chunk, parser)
        {count + length(messages), parser}
      end)

    assert message_count == 502
    assert parser.buffer == <<>>
    assert parser.state_machine == :connected

    if Map.has_key?(Map.from_struct(parser), :partial_messages) do
      assert %{
               4 => %{
                 header: %{chunk_stream_id: 4, type_id: 9, body_size: 18_933, timestamp: 8_100},
                 bytes_received: 12_288
               }
             } = parser.partial_messages
    end
  end

  defp decode_chunks(data) do
    Stream.unfold(data, fn
      <<len::little-32, chunk::binary-size(len), rest::binary>> -> {chunk, rest}
      <<>> -> nil
    end)
    |> Enum.to_list()
  end
end
