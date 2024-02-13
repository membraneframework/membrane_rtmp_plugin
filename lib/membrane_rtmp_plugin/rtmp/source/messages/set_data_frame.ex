defmodule Membrane.RTMP.Messages.SetDataFrame do
  @moduledoc """
  Defines the RTMP `setDataFrame` command.
  """

  @behaviour Membrane.RTMP.Message

  alias Membrane.RTMP.AMF0.Encoder
  alias Membrane.RTMP.Messages.OnExpectAdditionalMedia

  defstruct ~w(duration file_size encoder width height video_codec_id video_data_rate framerate audio_codec_id
                audio_data_rate audio_sample_rate audio_sample_size stereo)a

  @attributes_to_keys %{
    "duration" => :duration,
    "fileSize" => :file_size,
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

  @impl true
  def from_data(["@setDataFrame", "onExpectAdditionalMedia", _properties] = data) do
    OnExpectAdditionalMedia.from_data(data)
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
