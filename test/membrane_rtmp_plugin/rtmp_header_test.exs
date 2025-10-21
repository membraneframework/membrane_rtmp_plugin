defmodule Membrane.RTMP.HeaderTest do
  use ExUnit.Case, async: true

  alias Membrane.RTMP.Header

  describe "Extended Chunk Stream ID encoding" do
    test "deserialize header with 2-byte chunk stream ID format (ID 64)" do
      # Spec: When 6-bit field is 0, the ID is (second byte + 64)
      # For chunk stream ID 64: second byte should be 0 (64 - 64 = 0)
      # Header type 0 (0b00) with chunk_stream_id_marker=0
      # Format: [fmt:2 | cs_id:6] [cs_id-64:8] [timestamp:24] [body_size:24] [type_id:8] [stream_id:32]

      chunk_stream_id = 64
      timestamp = 1000
      body_size = 256
      # audio
      type_id = 8
      stream_id = 1

      binary =
        <<
          # Header type 0 with chunk_stream_id field = 0 (indicates 2-byte format)
          0b00::2,
          0::6,
          # Second byte: chunk_stream_id - 64
          chunk_stream_id - 64::8,
          # Standard header fields
          timestamp::24,
          body_size::24,
          type_id::8,
          stream_id::little-32
        >>

      {header, <<>>} = Header.deserialize(binary, nil)

      assert header.chunk_stream_id == chunk_stream_id
      assert header.timestamp == timestamp
      assert header.body_size == body_size
      assert header.type_id == type_id
      assert header.stream_id == stream_id
    end

    test "deserialize header with 2-byte chunk stream ID format (ID 319)" do
      # For chunk stream ID 319: second byte should be 255 (319 - 64 = 255)
      chunk_stream_id = 319
      timestamp = 2000
      body_size = 512
      # video
      type_id = 9
      stream_id = 1

      binary =
        <<
          0b00::2,
          0::6,
          chunk_stream_id - 64::8,
          timestamp::24,
          body_size::24,
          type_id::8,
          stream_id::little-32
        >>

      {header, <<>>} = Header.deserialize(binary, nil)

      assert header.chunk_stream_id == chunk_stream_id
      assert header.timestamp == timestamp
      assert header.body_size == body_size
    end

    test "deserialize header with 3-byte chunk stream ID format (ID 320)" do
      # Spec: When 6-bit field is 1, the ID is ((third byte)*256 + (second byte) + 64)
      # For chunk stream ID 320: (third byte)*256 + (second byte) + 64 = 320
      # So: (third byte)*256 + (second byte) = 256
      # third byte = 1, second byte = 0

      chunk_stream_id = 320
      timestamp = 3000
      body_size = 1024
      type_id = 8
      stream_id = 1

      # Calculate bytes for 3-byte format
      # = 256
      id_minus_64 = chunk_stream_id - 64
      # = 0
      second_byte = rem(id_minus_64, 256)
      # = 1
      third_byte = div(id_minus_64, 256)

      binary =
        <<
          # Header type 0 with chunk_stream_id field = 1 (indicates 3-byte format)
          0b00::2,
          1::6,
          # Second and third bytes for extended ID
          second_byte::8,
          third_byte::8,
          # Standard header fields
          timestamp::24,
          body_size::24,
          type_id::8,
          stream_id::little-32
        >>

      {header, <<>>} = Header.deserialize(binary, nil)

      assert header.chunk_stream_id == chunk_stream_id
      assert header.timestamp == timestamp
      assert header.body_size == body_size
    end

    test "deserialize header with 3-byte chunk stream ID format (ID 65599)" do
      # Maximum chunk stream ID supported by 3-byte format
      chunk_stream_id = 65599
      timestamp = 4000
      body_size = 2048
      type_id = 9
      stream_id = 1

      # = 65535
      id_minus_64 = chunk_stream_id - 64
      # = 255
      second_byte = rem(id_minus_64, 256)
      # = 255
      third_byte = div(id_minus_64, 256)

      binary =
        <<
          0b00::2,
          1::6,
          second_byte::8,
          third_byte::8,
          timestamp::24,
          body_size::24,
          type_id::8,
          stream_id::little-32
        >>

      {header, <<>>} = Header.deserialize(binary, nil)

      assert header.chunk_stream_id == chunk_stream_id
      assert header.timestamp == timestamp
      assert header.body_size == body_size
    end

    test "deserialize header type 1 with 2-byte chunk stream ID" do
      # Test extended chunk stream ID with header type 1 (no stream_id)
      chunk_stream_id = 100
      timestamp_delta = 500
      body_size = 128
      type_id = 8

      # Create a previous header for type 1 deserialization
      previous_header = %Header{
        chunk_stream_id: chunk_stream_id,
        timestamp: 1000,
        body_size: 100,
        type_id: 8,
        stream_id: 1
      }

      binary =
        <<
          0b01::2,
          0::6,
          chunk_stream_id - 64::8,
          timestamp_delta::24,
          body_size::24,
          type_id::8
        >>

      {header, <<>>} = Header.deserialize(binary, %{chunk_stream_id => previous_header})

      assert header.chunk_stream_id == chunk_stream_id
      assert header.timestamp == previous_header.timestamp + timestamp_delta
      assert header.body_size == body_size
      assert header.stream_id == previous_header.stream_id
    end

    test "deserialize header type 2 with 3-byte chunk stream ID" do
      # Test extended chunk stream ID with header type 2 (only timestamp delta)
      chunk_stream_id = 500
      timestamp_delta = 42

      id_minus_64 = chunk_stream_id - 64
      second_byte = rem(id_minus_64, 256)
      third_byte = div(id_minus_64, 256)

      previous_header = %Header{
        chunk_stream_id: chunk_stream_id,
        timestamp: 2000,
        body_size: 256,
        type_id: 9,
        stream_id: 1
      }

      binary =
        <<
          0b10::2,
          1::6,
          second_byte::8,
          third_byte::8,
          timestamp_delta::24
        >>

      {header, <<>>} = Header.deserialize(binary, %{chunk_stream_id => previous_header})

      assert header.chunk_stream_id == chunk_stream_id
      assert header.timestamp == previous_header.timestamp + timestamp_delta
      assert header.body_size == previous_header.body_size
      assert header.type_id == previous_header.type_id
    end

    test "deserialize header type 3 with 2-byte chunk stream ID" do
      # Test extended chunk stream ID with header type 3 (no new fields)
      chunk_stream_id = 200

      previous_header = %Header{
        chunk_stream_id: chunk_stream_id,
        timestamp: 3000,
        timestamp_delta: 100,
        body_size: 512,
        type_id: 8,
        stream_id: 1,
        extended_timestamp?: false
      }

      binary =
        <<
          0b11::2,
          0::6,
          chunk_stream_id - 64::8
        >>

      {header, <<>>} = Header.deserialize(binary, %{chunk_stream_id => previous_header})

      assert header.chunk_stream_id == chunk_stream_id
      assert header.timestamp == previous_header.timestamp + previous_header.timestamp_delta
    end

    test "serialize header with 2-byte chunk stream ID format" do
      # Test serialization of headers with extended chunk stream IDs
      header = %Header{
        chunk_stream_id: 150,
        timestamp: 5000,
        body_size: 1024,
        type_id: 9,
        stream_id: 1
      }

      binary = Header.serialize(header)

      # Verify it can be deserialized back
      {deserialized, <<>>} = Header.deserialize(binary, nil)
      assert deserialized.chunk_stream_id == header.chunk_stream_id
      assert deserialized.timestamp == header.timestamp
      assert deserialized.body_size == header.body_size
    end

    test "serialize header with 3-byte chunk stream ID format" do
      # Test serialization with large chunk stream ID
      header = %Header{
        chunk_stream_id: 1000,
        timestamp: 6000,
        body_size: 2048,
        type_id: 8,
        stream_id: 1
      }

      binary = Header.serialize(header)

      # Verify it can be deserialized back
      {deserialized, <<>>} = Header.deserialize(binary, nil)
      assert deserialized.chunk_stream_id == header.chunk_stream_id
      assert deserialized.timestamp == header.timestamp
      assert deserialized.body_size == header.body_size
    end

    test "round-trip for chunk stream ID boundary values" do
      # Test boundary values between different formats
      test_ids = [
        # Minimum single-byte
        2,
        # Maximum single-byte
        63,
        # Minimum 2-byte
        64,
        # Maximum 2-byte
        319,
        # Minimum 3-byte
        320,
        # Maximum 3-byte
        65599
      ]

      for chunk_stream_id <- test_ids do
        header = %Header{
          chunk_stream_id: chunk_stream_id,
          timestamp: 1000,
          body_size: 100,
          type_id: 8,
          stream_id: 1
        }

        binary = Header.serialize(header)
        {deserialized, <<>>} = Header.deserialize(binary, nil)

        assert deserialized.chunk_stream_id == chunk_stream_id,
               "Failed round-trip for chunk_stream_id #{chunk_stream_id}"
      end
    end
  end

  describe "Standard Chunk Stream ID encoding (existing behavior)" do
    test "deserialize header with standard 6-bit chunk stream ID" do
      # This test should pass with current implementation
      chunk_stream_id = 5
      timestamp = 1000
      body_size = 256
      type_id = 8
      stream_id = 1

      binary =
        <<
          0b00::2,
          chunk_stream_id::6,
          timestamp::24,
          body_size::24,
          type_id::8,
          stream_id::little-32
        >>

      {header, <<>>} = Header.deserialize(binary, nil)

      assert header.chunk_stream_id == chunk_stream_id
      assert header.timestamp == timestamp
      assert header.body_size == body_size
    end

    test "serialize header with standard chunk stream ID" do
      # This should work with current implementation
      header = %Header{
        chunk_stream_id: 10,
        timestamp: 2000,
        body_size: 512,
        type_id: 9,
        stream_id: 1
      }

      binary = Header.serialize(header)

      expected =
        <<
          0b00::2,
          10::6,
          2000::24,
          512::24,
          9::8,
          1::little-32
        >>

      assert binary == expected
    end
  end
end
