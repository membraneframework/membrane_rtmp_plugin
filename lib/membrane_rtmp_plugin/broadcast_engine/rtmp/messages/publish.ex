defmodule BroadcastEngine.RTMP.Messages.Publish do
  @moduledoc false

  @behaviour BroadcastEngine.RTMP.Message

  alias BroadcastEngine.RTMP.AMFEncoder

  @enforce_keys [:stream_key, :publish_type]
  defstruct [tx_id: 0] ++ @enforce_keys

  @type t :: %__MODULE__{
          stream_key: String.t(),
          publish_type: String.t(),
          tx_id: non_neg_integer()
        }

  @name "publish"

  @impl true
  def from_data([@name, tx_id, :null, stream_key, publish_type]) do
    %__MODULE__{tx_id: tx_id, stream_key: stream_key, publish_type: publish_type}
  end

  defimpl BroadcastEngine.RTMP.Messages.Serializer do
    require BroadcastEngine.RTMP.Header

    alias BroadcastEngine.RTMP.AMFEncoder

    @impl true
    def serialize(%@for{tx_id: tx_id, stream_key: stream_key, publish_type: publish_type}) do
      AMFEncoder.encode(["publish", tx_id, :null, stream_key, publish_type])
    end

    @impl true
    def type(%@for{}), do: BroadcastEngine.RTMP.Header.type(:amf_command)
  end
end
