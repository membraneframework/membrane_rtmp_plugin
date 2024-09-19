defmodule Membrane.RTMP.Messages.OnMetaData do
  @moduledoc """
  Defines the RTMP `onMetaData` command (sent by nginx client).
  """

  @behaviour Membrane.RTMP.Message

  alias Membrane.RTMP.AMF0.Encoder

  @attributes_to_keys %{
    "duration" => :duration,
    "width" => :width,
    "height" => :height,
    "videocodecid" => :video_codec_id,
    "videodatarate" => :video_data_rate,
    "framerate" => :framerate,
    "audiocodecid" => :audio_codec_id,
    "audiodatarate" => :audio_data_rate
  }

  @keys_to_attributes Map.new(@attributes_to_keys, fn {key, value} -> {value, key} end)

  defstruct Map.keys(@keys_to_attributes)

  @type t :: %__MODULE__{
          duration: number(),
          # video related
          width: number(),
          height: number(),
          video_codec_id: number(),
          video_data_rate: number(),
          framerate: number(),
          # audio related
          audio_codec_id: number(),
          audio_data_rate: number()
        }

  @impl true
  def from_data(["onMetaData", properties]) do
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
