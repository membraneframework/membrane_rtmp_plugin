defmodule BroadcastEngine.RTMP.Messages.FCPublish do
  @moduledoc false

  @behaviour BroadcastEngine.RTMP.Message

  alias BroadcastEngine.RTMP.AMFEncoder

  @enforce_keys [:stream_key]
  defstruct [tx_id: 0] ++ @enforce_keys

  @type t :: %__MODULE__{
          stream_key: String.t(),
          tx_id: non_neg_integer()
        }

  @name "FCPublish"

  @impl true
  def from_data([@name, tx_id, :null, stream_key]) do
    %__MODULE__{tx_id: tx_id, stream_key: stream_key}
  end

  defimpl BroadcastEngine.RTMP.Messages.Serializer do
    require BroadcastEngine.RTMP.Header

    alias BroadcastEngine.RTMP.AMFEncoder

    @impl true
    def serialize(%@for{tx_id: tx_id, stream_key: stream_key}) do
      AMFEncoder.encode(["FCPublish", tx_id, :null, stream_key])
    end

    @impl true
    def type(%@for{}), do: BroadcastEngine.RTMP.Header.type(:amf_command)
  end
end
