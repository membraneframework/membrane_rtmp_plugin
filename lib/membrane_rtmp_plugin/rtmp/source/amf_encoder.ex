defmodule Membrane.RTMP.AMFEncoder do
  @moduledoc false

  @type basic_object_t :: float() | String.t() | map() | :null
  @type list_entry_t :: {key :: String.t(), basic_object_t()}
  @type object_t :: basic_object_t() | [list_entry_t()]

  @object_end_marker <<0x00, 0x00, 0x09>>

  @spec encode(object_t() | [object_t]) :: binary()
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
  defp do_encode_object(object) when is_binary(object) do
    <<0x02, byte_size(object)::16, object::binary>>
  end

  defp do_encode_object(object) when is_map(object) or is_list(object) do
    id =
      if is_map(object) do
        0x03
      else
        0x08
      end

    IO.iodata_to_binary([id, Enum.map(object, &encode_key_value_pair/1), @object_end_marker])
  end

  defp do_encode_object(:null), do: <<0x05>>

  defp encode_key_value_pair({key, value}) do
    [<<byte_size(key)::16>>, key, do_encode_object(value)]
  end
end
