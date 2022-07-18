defmodule Membrane.RTMP.Messages.SetDataFrame do
  @moduledoc false

  @behaviour Membrane.RTMP.Message

  alias Membrane.RTMP.AMFEncoder

  @enforce_keys ~w(
    duration file_size
    width height video_codec_id video_data_rate framerate
    audio_codec_id audio_data_rate audio_sample_rate audio_sample_size stereo
    encoder
  )a
  defstruct @enforce_keys

  @attributes_to_keys %{
    "duration" => :duration,
    "filesize" => :file_size,
    "width" => :width,
    "height" => :height,
    "videocodecid" => :video_codec_id,
    "videodatarate" => :video_data_rate,
    "framerate" => :framerate,
    "audiocodecid" => :audio_codec_id,
    "audiodatarate" => :audio_data_rate,
    "audiosamplerate" => :audio_sample_rate,
    "audiosamplesize" => :audio_sample_size,
    "stereo" => :stereo,
    "encoder" => :encoder
  }

  @keys_to_attributes Map.new(@attributes_to_keys, fn {key, value} -> {value, key} end)

  @type t :: %__MODULE__{
          duration: number(),
          file_size: number(),
          # video related
          width: number(),
          height: number(),
          video_codec_id: number(),
          video_data_rate: number(),
          framerate: number(),
          # audio related
          audio_codec_id: number(),
          audio_data_rate: number(),
          audio_sample_rate: number(),
          audio_sample_size: number(),
          stereo: boolean()
        }

  @impl true
  def from_data(["@setDataFrame", "onMetaData", properties]) do
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
    message
    |> Map.from_struct()
    |> Enum.map(fn {key, value} -> {Map.fetch!(@keys_to_attributes, key), value} end)
    |> Map.new()
  end

  defimpl Membrane.RTMP.Messages.Serializer do
    require Membrane.RTMP.Header

    alias Membrane.RTMP.AMFEncoder

    @impl true
    def serialize(%@for{} = message) do
      AMFEncoder.encode([@for.to_map(message)])
    end

    @impl true
    def type(%@for{}), do: Membrane.RTMP.Header.type(:amf_data)
  end
end
