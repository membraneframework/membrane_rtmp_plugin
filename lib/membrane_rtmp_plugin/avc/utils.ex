defmodule Membrane.AVC.Utils do
  @moduledoc false

  @spec to_annex_b(binary()) :: binary()
  def to_annex_b(<<length::32, data::binary-size(length), rest::binary>>),
    do: <<0, 0, 1>> <> data <> to_annex_b(rest)

  def to_annex_b(_otherwise), do: <<>>
end
