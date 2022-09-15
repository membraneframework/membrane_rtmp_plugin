defmodule Membrane.RTMP.Messages.Anonymous do
  @moduledoc false

  @behaviour Membrane.RTMP.Message

  alias Membrane.RTMP.Messages.Serializer

  @enforce_keys [:name, :properties]
  defstruct [tx_id: nil] ++ @enforce_keys

  @type t :: %__MODULE__{
          name: String.t(),
          properties: any(),
          tx_id: non_neg_integer() | nil
        }

  @impl true
  def from_data([name, tx_id | properties]) when is_binary(name) do
    %__MODULE__{name: name, tx_id: tx_id, properties: properties}
  end

  def from_data([name]) when is_binary(name) do
    %__MODULE__{name: name, tx_id: nil, properties: []}
  end

  defimpl Serializer do
    require Membrane.RTMP.Header

    alias Membrane.RTMP.AMFEncoder

    @impl true
    def serialize(%@for{name: name, tx_id: nil, properties: properties}) do
      AMFEncoder.encode([name | properties])
    end

    def serialize(%@for{name: name, tx_id: tx_id, properties: properties}) do
      AMFEncoder.encode([name, tx_id | properties])
    end

    @impl true
    def type(%@for{}), do: Membrane.RTMP.Header.type(:amf_command)
  end
end
