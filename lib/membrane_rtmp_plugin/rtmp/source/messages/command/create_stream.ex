defmodule Membrane.RTMP.Messages.CreateStream do
  @moduledoc false

  @behaviour Membrane.RTMP.Message

  alias Membrane.RTMP.AMF.Encoder

  defstruct tx_id: 0

  @type t :: %__MODULE__{
          tx_id: non_neg_integer()
        }

  @name "createStream"

  @impl true
  def from_data([@name, tx_id, :null]) do
    %__MODULE__{tx_id: tx_id}
  end

  defimpl Membrane.RTMP.Messages.Serializer do
    require Membrane.RTMP.Header

    @impl true
    def serialize(%@for{tx_id: tx_id}) do
      Encoder.encode(["createStream", tx_id, :null])
    end

    @impl true
    def type(%@for{}), do: Membrane.RTMP.Header.type(:amf_command)
  end
end
