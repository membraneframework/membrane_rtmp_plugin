defmodule Membrane.RTMP.Messages.Audio do
  @moduledoc false

  @behaviour Membrane.RTMP.Message

  @enforce_keys [:data]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          data: binary()
        }

  @impl true
  def deserialize(<<data::binary>>) do
    %__MODULE__{data: data}
  end

  defimpl Membrane.RTMP.Messages.Serializer do
    require Membrane.RTMP.Header

    @impl true
    def serialize(%@for{data: data}) do
      data
    end

    @impl true
    def type(%@for{}), do: Membrane.RTMP.Header.type(:audio_message)
  end
end
