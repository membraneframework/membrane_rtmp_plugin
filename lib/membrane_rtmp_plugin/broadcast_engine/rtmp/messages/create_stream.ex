defmodule BroadcastEngine.RTMP.Messages.CreateStream do
  @moduledoc false

  @behaviour BroadcastEngine.RTMP.Message

  alias BroadcastEngine.RTMP.AMFEncoder

  defstruct tx_id: 0

  @type t :: %__MODULE__{
          tx_id: non_neg_integer()
        }

  @name "createStream"

  @impl true
  def from_data([@name, tx_id, :null]) do
    %__MODULE__{tx_id: tx_id}
  end

  defimpl BroadcastEngine.RTMP.Messages.Serializer do
    require BroadcastEngine.RTMP.Header

    alias BroadcastEngine.RTMP.AMFEncoder

    @impl true
    def serialize(%@for{tx_id: tx_id}) do
      AMFEncoder.encode(["createStream", tx_id, :null])
    end

    @impl true
    def type(%@for{}), do: BroadcastEngine.RTMP.Header.type(:amf_command)
  end
end
