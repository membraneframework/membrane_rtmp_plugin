defmodule Membrane.RTMP.AMF3.Parser do
  @moduledoc false

  import Bitwise

  @doc """
  Parses message from AMF3 format to elixir data types.
  """
  @spec parse_list(binary()) :: list()
  def parse_list(binary) do
    do_parse(binary, [])
  end

  @doc """
  Parses message from AMF3 format to elixir data type.
  """
  @spec parse(binary()) :: {value :: term(), rest :: binary()}
  def parse(binary) do
    parse_value(binary)
  end

  defp do_parse(<<>>, acc), do: Enum.reverse(acc)

  defp do_parse(payload, acc) do
    {value, rest} = parse_value(payload)

    do_parse(rest, [value | acc])
  end

  # undefined
  defp parse_value(<<0x00, rest::binary>>) do
    {:undefined, rest}
  end

  # null
  defp parse_value(<<0x01, rest::binary>>) do
    {nil, rest}
  end

  # false
  defp parse_value(<<0x02, rest::binary>>) do
    {false, rest}
  end

  # true
  defp parse_value(<<0x03, rest::binary>>) do
    {true, rest}
  end

  # integer
  defp parse_value(<<0x04, rest::binary>>) do
    parse_integer(rest)
  end

  # double
  defp parse_value(<<0x05, double::float-size(64), rest::binary>>) do
    {double, rest}
  end

  # string
  defp parse_value(<<0x06, rest::binary>>) do
    parse_string(rest)
  end

  # xml document
  defp parse_value(<<0x07, rest::binary>>) do
    {size, rest} = parse_integer(rest)

    # if the bit is set then we are dealing with string literal
    if (size &&& 0x01) == 1 do
      size = size >>> 1

      <<string::binary-size(size), rest::binary>> = rest

      {{:xml_doc, string}, rest}
    else
      raise "Unsupported xml doc reference"
    end
  end

  # date
  defp parse_value(<<0x08, rest::binary>>) do
    {number, rest} = parse_integer(rest)

    if (number &&& 0x01) == 1 do
      {{:date, :previous}, rest}
    else
      <<date::float-size(64), rest::binary>> = rest

      {{:date, date}, rest}
    end
  end

  # array
  defp parse_value(<<0x09, rest::binary>>) do
    {size, rest} = parse_integer(rest)

    if (size &&& 0x01) == 1 do
      dense_array_size = size >>> 1

      {assoc_array, rest} = parse_assoc_array(rest, [])
      {dense_array, rest} = parse_dense_array(rest, dense_array_size, [])

      {assoc_array ++ dense_array, rest}
    else
      raise "Unsupported array reference"
    end
  end

  # object
  defp parse_value(<<0x0A, _rest::binary>>) do
    raise "Unsupported object type"
  end

  # xml
  defp parse_value(<<0x0B, rest::binary>>) do
    {size, rest} = parse_integer(rest)

    # if the bit is set then we are dealing with string literal
    if (size &&& 0x01) == 1 do
      size = size >>> 1

      <<string::binary-size(size), rest::binary>> = rest

      {{:xml, string}, rest}
    else
      raise "Unsupported xml reference"
    end
  end

  # byte array
  defp parse_value(<<0x0C, rest::binary>>) do
    {size, rest} = parse_integer(rest)

    if (size &&& 0x01) == 1 do
      size = size >>> 1

      <<bytes::binary-size(size), rest::binary>> = rest

      {bytes, rest}
    else
      raise "Unsupported byte array reference"
    end
  end

  # vector int
  defp parse_value(<<0x0D, _rest::binary>>) do
    raise "Unsupported vector int type"
  end

  # vector uint
  defp parse_value(<<0x0E, _rest::binary>>) do
    raise "Unsupported vector uint type"
  end

  # vector double
  defp parse_value(<<0x0F, _rest::binary>>) do
    raise "Unsupported vector double type"
  end

  # vector object
  defp parse_value(<<0x10, _rest::binary>>) do
    raise "Unsupported vector object type"
  end

  # dictionary
  defp parse_value(<<0x11, _rest::binary>>) do
    raise "Unsupported dictionary type"
  end

  defp parse_integer(<<0::1, value::7, rest::binary>>), do: {value, rest}

  defp parse_integer(<<1::1, first::7, 0::1, second::7, rest::binary>>) do
    {bsl(first, 7) + second, rest}
  end

  defp parse_integer(<<1::1, first::7, 1::1, second::7, 0::1, third::7, rest::binary>>) do
    {bsl(first, 14) + bsl(second, 7) + third, rest}
  end

  defp parse_integer(<<1::1, first::7, 1::1, second::7, 0::1, third::7, fourth::8, rest::binary>>) do
    {bsl(first, 22) + bsl(second, 15) + bsl(third, 7) + fourth, rest}
  end

  defp parse_string(payload) do
    {size, rest} = parse_integer(payload)

    # if the bit is set then we are dealing with string literal
    if (size &&& 0x01) == 1 do
      size = size >>> 1

      <<string::binary-size(size), rest::binary>> = rest

      {string, rest}
    else
      raise "Unsupported string reference"
    end
  end

  defp parse_assoc_array(<<0x01, rest::binary>>, acc), do: {Enum.reverse(acc), rest}

  defp parse_assoc_array(payload, acc) do
    {key, rest} = parse_string(payload)
    {value, rest} = parse_value(rest)

    parse_assoc_array(rest, [{key, value} | acc])
  end

  defp parse_dense_array(rest, 0, acc), do: {Enum.reverse(acc), rest}

  defp parse_dense_array(rest, size, acc) do
    {value, rest} = parse_value(rest)

    parse_dense_array(rest, size - 1, [value | acc])
  end
end
