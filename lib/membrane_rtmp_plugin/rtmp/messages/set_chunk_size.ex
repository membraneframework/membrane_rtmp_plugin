defmodule Membrane.RTMP.Messages.SetChunkSize do
  @moduledoc false

  @behaviour Membrane.RTMP.Message

  @enforce_keys [:chunk_size]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          chunk_size: String.t()
        }

  @impl true
  def deserialize(<<0::1, chunk_size::31>>) do
    %__MODULE__{chunk_size: chunk_size}
  end

  defimpl Membrane.RTMP.Messages.Serializer do
    require Membrane.RTMP.Header

    @impl true
    def serialize(%@for{chunk_size: chunk_size}) do
      <<0::1, chunk_size::31>>
    end

    @impl true
    def type(%@for{}), do: Membrane.RTMP.Header.type(:set_chunk_size)
  end
end
