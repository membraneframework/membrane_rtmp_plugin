defmodule Membrane.RTMP.AMF3.Parser do
  @moduledoc false

  import Bitwise

  @doc """
  Parses message from [AMF3](https://en.wikipedia.org/wiki/Action_Message_Format#AMF3) format to Erlang terms.
  """
  @spec parse(binary()) :: list()
  def parse(binary) do
    do_parse(binary, [])
  end

  @doc """
  Parses a single message from [AMF3](https://en.wikipedia.org/wiki/Action_Message_Format#AMF3) format to Erlang terms.
  """
  @spec parse_one(binary()) :: {value :: term(), rest :: binary()}
  def parse_one(binary) do
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
    case check_value_type(rest) do
      {:value, size, rest} ->
        <<string::binary-size(size), rest::binary>> = rest

        {{:xml, string}, rest}

      {:ref, ref, rest} ->
        {{:ref, {:xml, ref}}, rest}
    end
  end

  # date
  defp parse_value(<<0x08, rest::binary>>) do
    case check_value_type(rest) do
      {:value, _value, rest} ->
        <<date::float-size(64), rest::binary>> = rest

        {DateTime.from_unix!(trunc(date), :millisecond), rest}

      {:ref, ref, rest} ->
        {{:ref, {:date, ref}}, rest}
    end
  end

  # array
  defp parse_value(<<0x09, rest::binary>>) do
    case check_value_type(rest) do
      {:value, dense_array_size, rest} ->
        {assoc_array, rest} = parse_assoc_array(rest, [])
        {dense_array, rest} = parse_dense_array(rest, dense_array_size, [])

        {assoc_array ++ dense_array, rest}

      {:ref, ref, rest} ->
        {{:array_ref, ref}, rest}
    end
  end

  # object
  defp parse_value(<<0x0A, _rest::binary>>) do
    raise "Unsupported AMF3 type: object"
  end

  # xml
  defp parse_value(<<0x0B, rest::binary>>) do
    case check_value_type(rest) do
      {:value, size, rest} ->
        <<string::binary-size(size), rest::binary>> = rest

        {{:xml_script, string}, rest}

      {:ref, ref, rest} ->
        {{:ref, {:xml_script, ref}}, rest}
    end
  end

  # byte array
  defp parse_value(<<0x0C, rest::binary>>) do
    case check_value_type(rest) do
      {:value, size, rest} ->
        <<bytes::binary-size(size), rest::binary>> = rest

        {bytes, rest}

      {:ref, ref, rest} ->
        {{:ref, {:byte_array, ref}}, rest}
    end
  end

  # vector int
  defp parse_value(<<0x0D, _rest::binary>>) do
    raise "Unsupported AMF3 type: vector int"
  end

  # vector uint
  defp parse_value(<<0x0E, _rest::binary>>) do
    raise "Unsupported AMF3 type: vector uint"
  end

  # vector double
  defp parse_value(<<0x0F, _rest::binary>>) do
    raise "Unsupported AMF3 type: vector double"
  end

  # vector object
  defp parse_value(<<0x10, _rest::binary>>) do
    raise "Unsupported AMF3 type: vector object"
  end

  # dictionary
  defp parse_value(<<0x11, _rest::binary>>) do
    raise "Unsupported AMF3 type: dictionary"
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
    case check_value_type(payload) do
      {:value, size, rest} ->
        <<string::binary-size(size), rest::binary>> = rest

        {string, rest}

      {:ref, ref, rest} ->
        {{:ref, {:string, ref}}, rest}
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

  defp check_value_type(rest) do
    {number, rest} = parse_integer(rest)

    value = number >>> 1

    if (number &&& 0x01) == 1 do
      {:value, value, rest}
    else
      {:ref, value, rest}
    end
  end
end
