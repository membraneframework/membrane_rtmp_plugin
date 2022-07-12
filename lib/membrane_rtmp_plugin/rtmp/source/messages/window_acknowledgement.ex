defmodule Membrane.RTMP.Messages.WindowAcknowledgement do
  @moduledoc false

  @behaviour Membrane.RTMP.Message

  @enforce_keys [:size]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          size: non_neg_integer()
        }

  @impl true
  def deserialize(<<size::32>>) do
    %__MODULE__{size: size}
  end

  defimpl Membrane.RTMP.Messages.Serializer do
    require Membrane.RTMP.Header

    @impl true
    def serialize(%@for{size: size}) do
      <<size::32>>
    end

    @impl true
    def type(%@for{}), do: Membrane.RTMP.Header.type(:window_acknowledgement_size)
  end
end
