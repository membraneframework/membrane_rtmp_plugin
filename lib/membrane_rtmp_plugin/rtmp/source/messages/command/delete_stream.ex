defmodule Membrane.RTMP.Messages.DeleteStream do
  @moduledoc false

  @behaviour Membrane.RTMP.Message

  alias Membrane.RTMP.AMF0.Encoder

  @enforce_keys [:stream_id]

  defstruct @enforce_keys ++ [tx_id: 0]

  @type t :: %__MODULE__{
          tx_id: non_neg_integer(),
          stream_id: non_neg_integer()
        }

  @name "deleteStream"

  @impl true
  def from_data([@name, tx_id, :null, stream_id]) do
    %__MODULE__{tx_id: tx_id, stream_id: stream_id}
  end

  defimpl Membrane.RTMP.Messages.Serializer do
    require Membrane.RTMP.Header

    @impl true
    def serialize(%@for{tx_id: tx_id, stream_id: stream_id}) do
      Encoder.encode(["deleteStream", tx_id, :null, stream_id])
    end

    @impl true
    def type(%@for{}), do: Membrane.RTMP.Header.type(:amf_command)
  end
end
