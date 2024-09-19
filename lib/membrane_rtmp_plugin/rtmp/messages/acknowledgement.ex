defmodule Membrane.RTMP.Messages.Acknowledgement do
  @moduledoc false

  @behaviour Membrane.RTMP.Message

  @enforce_keys [:sequence_number]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          sequence_number: non_neg_integer()
        }

  @impl true
  def deserialize(<<sequence_number::32>>) do
    %__MODULE__{sequence_number: sequence_number}
  end

  defimpl Membrane.RTMP.Messages.Serializer do
    require Membrane.RTMP.Header

    @impl true
    def serialize(%@for{sequence_number: sequence_number}) do
      <<sequence_number::32>>
    end

    @impl true
    def type(%@for{}), do: Membrane.RTMP.Header.type(:acknowledgement)
  end
end
