defmodule Membrane.RTMP.AMFParser do
  @moduledoc """
  Parser for AMF format.

  Supported types:
  - number
  - boolean
  - string
  - key-value pairs object
  - key-value pairs array
  """

  use Bitwise

  @doc """
  Parses message from AMF format to elixir data types.
  """
  @spec parse(binary()) :: list()
  def parse(binary) do
    do_parse(binary, [])
  end

  defp do_parse(<<>>, acc), do: Enum.reverse(acc)

  defp do_parse(payload, acc) do
    {value, rest} = parse_value(payload)

    do_parse(rest, [value | acc])
  end

  # parsing a number
  defp parse_value(<<0x00, number::float-size(64), rest::binary>>) do
    {number, rest}
  end

  # parsing a boolean
  defp parse_value(<<0x01, boolean::8, rest::binary>>) do
    case boolean do
      0 -> {true, rest}
      1 -> {false, rest}
    end
  end

  # parsing a string
  defp parse_value(<<0x02, size::16, rest::binary>>) do
    <<string::binary-size(size), rest::binary>> = rest

    {string, rest}
  end

  # parsing a key-value object
  defp parse_value(<<0x03, rest::binary>>) do
    {acc, rest} = parse_object_pairs(rest, [])

    {Map.new(acc), rest}
  end

  # parsing a null value
  defp parse_value(<<0x05, rest::binary>>) do
    {:null, rest}
  end

  defp parse_value(<<0x08, _array_size::32, rest::binary>>) do
    parse_object_pairs(rest, [])
  end

  # we reached object end
  defp parse_object_pairs(<<0x00, 0x00, 0x09, rest::binary>>, acc) do
    {Enum.reverse(acc), rest}
  end

  defp parse_object_pairs(
         <<key_size::16, key::binary-size(key_size), rest::binary>>,
         acc
       ) do
    {value, rest} = parse_value(rest)

    parse_object_pairs(rest, [{key, value} | acc])
  end
end
