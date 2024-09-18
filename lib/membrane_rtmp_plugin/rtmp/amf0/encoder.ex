defmodule Membrane.RTMP.AMF0.Encoder do
  @moduledoc false

  @type basic_object_t :: float() | boolean() | String.t() | map() | :null
  @type list_entry_t :: {key :: String.t(), basic_object_t() | nil}
  @type object_t :: basic_object_t() | [list_entry_t()]

  @object_end_marker <<0x00, 0x00, 0x09>>

  @doc """
  Encodes a message according to [AMF0](https://en.wikipedia.org/wiki/Action_Message_Format).
  """
  @spec encode(object_t() | [object_t()]) :: binary()
  def encode(objects) when is_list(objects) do
    objects
    |> Enum.map(&do_encode_object/1)
    |> IO.iodata_to_binary()
  end

  def encode(object) do
    do_encode_object(object)
  end

  # encode number
  defp do_encode_object(object) when is_number(object) do
    <<0x00, object::float-size(64)>>
  end

  # encode boolean
  defp do_encode_object(object) when is_boolean(object) do
    if object do
      <<0x01, 1::8>>
    else
      <<0x01, 0::8>>
    end
  end

  # encode string
  defp do_encode_object(object) when is_binary(object) and byte_size(object) < 65_535 do
    <<0x02, byte_size(object)::16, object::binary>>
  end

  defp do_encode_object(object) when is_map(object) or is_list(object) do
    id =
      if is_map(object) do
        0x03
      else
        0x08
      end

    [id, Enum.map(object, &encode_key_value_pair/1), @object_end_marker]
  end

  defp do_encode_object(:null), do: <<0x05>>

  defp encode_key_value_pair({_key, nil}), do: []

  defp encode_key_value_pair({<<key::binary>>, value}) when byte_size(key) < 65_535 do
    [<<byte_size(key)::16>>, key, do_encode_object(value)]
  end
end
