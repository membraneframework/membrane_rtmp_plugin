defmodule BroadcastEngine.RTMP.Messages.SetChunkSize do
  @moduledoc false

  @behaviour BroadcastEngine.RTMP.Message

  @enforce_keys [:chunk_size]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          chunk_size: String.t()
        }

  @impl true
  def deserialize(<<0::1, chunk_size::31>>) do
    %__MODULE__{chunk_size: chunk_size}
  end

  defimpl BroadcastEngine.RTMP.Messages.Serializer do
    require BroadcastEngine.RTMP.Header

    @impl true
    def serialize(%@for{chunk_size: chunk_size}) do
      <<0::1, chunk_size::31>>
    end

    @impl true
    def type(%@for{}), do: BroadcastEngine.RTMP.Header.type(:set_chunk_size)
  end
end
