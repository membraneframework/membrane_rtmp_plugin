defmodule Membrane.RTMP.Messages.ReleaseStream do
  @moduledoc """
  Defines the RTMP `releaseStream` command.
  """

  @behaviour Membrane.RTMP.Message

  alias Membrane.RTMP.AMF0.Encoder

  @enforce_keys [:stream_key]
  defstruct [tx_id: 0] ++ @enforce_keys

  @type t :: %__MODULE__{
          stream_key: String.t(),
          tx_id: non_neg_integer()
        }

  @name "releaseStream"

  @impl true
  def from_data([@name, tx_id, :null, stream_key]) do
    %__MODULE__{tx_id: tx_id, stream_key: stream_key}
  end

  defimpl Membrane.RTMP.Messages.Serializer do
    require Membrane.RTMP.Header

    @impl true
    def serialize(%@for{tx_id: tx_id, stream_key: stream_key}) do
      Encoder.encode(["releaseStream", tx_id, :null, stream_key])
    end

    @impl true
    def type(%@for{}), do: Membrane.RTMP.Header.type(:amf_command)
  end
end
