defmodule Membrane.RTMP.Messages.AdditionalMedia do
  @moduledoc false

  @behaviour Membrane.RTMP.Message

  alias Membrane.RTMP.AMF0.Encoder

  @enforce_keys [:id, :media]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: String.t(),
          media: binary()
        }

  @impl true
  def from_data(["additionalMedia", %{"id" => id, "media" => media}]) do
    %__MODULE__{id: id, media: media}
  end

  @doc false
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{id: id, media: media}) do
    # TODO: this media should be AMF3 encoded
    %{"id" => id, "media" => media}
  end

  defimpl Membrane.RTMP.Messages.Serializer do
    require Membrane.RTMP.Header

    @impl true
    def serialize(%@for{} = message) do
      Encoder.encode([@for.to_map(message)])
    end

    @impl true
    def type(%@for{}), do: Membrane.RTMP.Header.type(:amf_data)
  end
end
