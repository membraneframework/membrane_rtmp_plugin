defmodule Membrane.RTMP.Header do
  @moduledoc false

  @enforce_keys [:chunk_stream_id, :type_id]
  defstruct @enforce_keys ++
              [
                body_size: 0,
                timestamp: 0,
                timestamp_delta: 0,
                extended_timestamp?: false,
                stream_id: 0
              ]

  @typedoc """
  RTMP header structure.

  Fields:
  * `chunk_stream_id` - chunk stream identifier that the following packet body belongs to
  * `timestmap` - chunk timestamp, equals 0 when the header is a part of non-media message
  * `body_size` - the size in bytes of the following body payload
  * `type_id` - the type of the body payload, for more details please refer to the RTMP docs
  * `stream_id` - stream identifier that the message belongs to
  """
  @type t :: %__MODULE__{
          chunk_stream_id: integer(),
          timestamp: integer(),
          body_size: integer(),
          type_id: integer(),
          stream_id: integer()
        }

  defmacro type(:set_chunk_size), do: 0x01
  defmacro type(:acknowledgement), do: 0x03
  defmacro type(:user_control_message), do: 0x04
  defmacro type(:window_acknowledgement_size), do: 0x05
  defmacro type(:set_peer_bandwidth), do: 0x06
  defmacro type(:audio_message), do: 0x08
  defmacro type(:video_message), do: 0x09
  defmacro type(:amf_data), do: 0x12
  defmacro type(:amf_command), do: 0x14

  @header_type_0 <<0x0::2>>
  @header_type_1 <<0x1::2>>
  @header_type_2 <<0x2::2>>
  @header_type_3 <<0x3::2>>

  @extended_timestamp_marker 0xFFFFFF

  @spec new(Keyword.t()) :: t()
  def new(opts) do
    struct!(__MODULE__, opts)
  end

  @doc """
  Deserializes given binary into an RTMP header structure.

  RTMP headers can be self contained or may depend on preceding headers.
  It depends on the first 2 bits of the header:
  * `0b00` - current header is self contained and contains all the header information, see `t:t/0`
  * `0b01` - current header derives the `stream_id` from the previous header
  * `0b10` - same as above plus derives `type_id` and `body_size`
  * `0b11` - all values are derived from the previous header with the same `chunk_stream_id`
  """
  @spec deserialize(binary(), t() | nil) :: {t(), rest :: binary()} | {:error, :need_more_data}
  def deserialize(binary, previous_headers \\ nil)

  # only the deserialization of the 0b00 type can have `nil` previous header
  def deserialize(
        <<@header_type_0::bitstring, chunk_stream_id::6, timestamp::24, body_size::24, type_id::8,
          stream_id::little-integer-size(32), rest::binary>>,
        _previous_headers
      ) do
    with {timestamp, extended_timestamp?, rest} <- extract_timestamp(rest, timestamp) do
      header = %__MODULE__{
        chunk_stream_id: chunk_stream_id,
        timestamp: timestamp,
        extended_timestamp?: extended_timestamp?,
        body_size: body_size,
        type_id: type_id,
        stream_id: stream_id
      }

      {header, rest}
    end
  end

  def deserialize(
        <<@header_type_1::bitstring, chunk_stream_id::6, timestamp_delta::24, body_size::24,
          type_id::8, rest::binary>>,
        previous_headers
      ) do
    with {timestamp_delta, extended_timestamp?, rest} <- extract_timestamp(rest, timestamp_delta) do
      header = %__MODULE__{
        chunk_stream_id: chunk_stream_id,
        timestamp: previous_headers[chunk_stream_id].timestamp + timestamp_delta,
        timestamp_delta: timestamp_delta,
        extended_timestamp?: extended_timestamp?,
        body_size: body_size,
        type_id: type_id,
        stream_id: previous_headers[chunk_stream_id].stream_id
      }

      {header, rest}
    end
  end

  def deserialize(
        <<@header_type_2::bitstring, chunk_stream_id::6, timestamp_delta::24, rest::binary>>,
        previous_headers
      ) do
    with {timestamp_delta, extended_timestamp?, rest} <- extract_timestamp(rest, timestamp_delta) do
      header = %__MODULE__{
        chunk_stream_id: chunk_stream_id,
        timestamp: previous_headers[chunk_stream_id].timestamp + timestamp_delta,
        timestamp_delta: timestamp_delta,
        extended_timestamp?: extended_timestamp?,
        body_size: previous_headers[chunk_stream_id].body_size,
        type_id: previous_headers[chunk_stream_id].type_id,
        stream_id: previous_headers[chunk_stream_id].stream_id
      }

      {header, rest}
    end
  end

  def deserialize(
        <<@header_type_3::bitstring, chunk_stream_id::6, rest::binary>>,
        previous_headers
      ) do
    %__MODULE__{} = previous_header = previous_headers[chunk_stream_id]

    if previous_header.extended_timestamp? do
      with {timestamp_delta, _extended_timestamp?, rest} <-
             extract_timestamp(rest, @extended_timestamp_marker) do
        header = %__MODULE__{
          previous_header
          | timestamp: previous_header.timestamp + timestamp_delta,
            timestamp_delta: timestamp_delta
        }

        {header, rest}
      end
    else
      header = %__MODULE__{
        previous_header
        | timestamp: previous_header.timestamp + previous_header.timestamp_delta
      }

      {header, rest}
    end
  end

  def deserialize(
        <<@header_type_0::bitstring, _chunk_stream_id::6, _rest::binary>>,
        _prev_header
      ),
      do: {:error, :need_more_data}

  def deserialize(
        <<@header_type_1::bitstring, _chunk_stream_id::6, _rest::binary>>,
        _prev_header
      ),
      do: {:error, :need_more_data}

  def deserialize(
        <<@header_type_2::bitstring, _chunk_stream_id::6, _rest::binary>>,
        _prev_header
      ),
      do: {:error, :need_more_data}

  @spec serialize(t()) :: binary()
  def serialize(%__MODULE__{} = header) do
    %{
      chunk_stream_id: chunk_stream_id,
      timestamp: timestamp,
      body_size: body_size,
      type_id: type_id,
      stream_id: stream_id
    } = header

    <<@header_type_0::bitstring, chunk_stream_id::6, timestamp::24, body_size::24, type_id::8,
      stream_id::little-integer-size(32)>>
  end

  defp extract_timestamp(<<timestamp::32, rest::binary>>, @extended_timestamp_marker),
    do: {timestamp, true, rest}

  defp extract_timestamp(_rest, @extended_timestamp_marker),
    do: {:error, :need_more_data}

  defp extract_timestamp(rest, timestamp),
    do: {timestamp, false, rest}
end
