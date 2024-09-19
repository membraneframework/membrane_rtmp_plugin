defmodule Membrane.RTMP.Messages.OnExpectAdditionalMedia do
  @moduledoc """
  Defines the RTMP `onExpectAdditionalMedia` command that is related to Twitch's RTMP additional
  media track message.

  The command is usually a part of `@setDataFrame` command but for more convencience it is
  extracted.
  """

  @behaviour Membrane.RTMP.Message

  alias Membrane.RTMP.AMF0.Encoder

  @attributes_to_keys %{
    "additionalMedia" => :additional_media,
    "defaultMedia" => :default_media,
    "processingIntents" => :processing_intents
  }

  @keys_to_attributes Map.new(@attributes_to_keys, fn {key, value} -> {value, key} end)

  defstruct Map.keys(@keys_to_attributes)

  @type t :: %__MODULE__{
          additional_media: map(),
          default_media: map(),
          processing_intents: [String.t()]
        }

  @impl true
  def from_data(["@setDataFrame", "onExpectAdditionalMedia", properties]) do
    new(properties)
  end

  @spec new([{String.t(), any()}]) :: t()
  def new(options) do
    params =
      options
      |> Map.new()
      |> Map.take(Map.keys(@attributes_to_keys))
      |> Enum.map(fn {key, value} ->
        {Map.fetch!(@attributes_to_keys, key), value}
      end)

    struct!(__MODULE__, params)
  end

  # helper for message serialization
  @doc false
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = message) do
    Map.new(message, fn {key, value} -> {Map.fetch!(@keys_to_attributes, key), value} end)
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
