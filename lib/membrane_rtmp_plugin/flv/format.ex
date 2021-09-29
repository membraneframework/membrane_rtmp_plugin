defmodule Membrane.FLV do
  @moduledoc """
  Capabilities for Flash Video (FLV) container
  """
  @enforce_keys [:mode]
  defstruct @enforce_keys ++
              [
                audio: nil,
                video: nil
              ]

  @typedoc """
  Description of mode in which the FLV container is streamed:
    - `:packets` means that the FLV header is transmitted in the very first buffer, then only the packets from inside the container are sent.
      This mode will be use when eg. reading an FLV file
    - `:frames` means that each buffer contains a full FLV container. This is highly unlikely to ever be seen.
  """
  @type mode_t() :: :packets | :frames

  @sound_format BiMap.new(%{
                  0 => :pcm,
                  1 => :adpcm,
                  2 => :MP3,
                  # PCM little endian
                  3 => :pcmle,
                  4 => :nellymoser_16k_mono,
                  5 => :nellymoser_8k_mono,
                  6 => :nellymoser,
                  7 => :g711_a_law,
                  8 => :g711_mu_law,
                  10 => :AAC,
                  11 => :Speex,
                  14 => :MP3_8k,
                  15 => :device_specific
                })

  @type sound_format_t() ::
          :pcm
          | :adpcm
          | :MP3
          | :pcmle
          | :nellymoser_16k_mono
          | :nellymoser_8k_mono
          | :nellymoser
          | :g711_a_law
          | :g711_mu_law
          | :AAC
          | :Speex
          | :MP3_8k
          | :device_specific

  @video_codec BiMap.new(%{
                 2 => :sorenson_h263,
                 3 => :screen_video,
                 4 => :vp6,
                 5 => :vp6_with_alpha,
                 6 => :screen_video_2,
                 7 => :H264
               })

  @type video_codec_t() ::
          :sorenson_h263 | :screen_video | :vp6 | :vp6_with_alpha | :screen_video_2 | :H264

  @type t() :: %__MODULE__{
          mode: mode_t(),
          audio: nil | sound_format_t(),
          video: nil | video_codec_t()
        }

  @spec index_to_sound_format(non_neg_integer()) :: sound_format_t()
  def index_to_sound_format(index), do: BiMap.fetch!(@sound_format, index)

  @spec sound_format_to_index(sound_format_t()) :: non_neg_integer()
  def sound_format_to_index(format), do: BiMap.fetch_key!(@sound_format, format)

  @spec index_to_video_codec(non_neg_integer()) :: video_codec_t()
  def index_to_video_codec(index), do: BiMap.fetch!(@video_codec, index)

  @spec video_codec_to_index(video_codec_t()) :: non_neg_integer()
  def video_codec_to_index(codec), do: BiMap.fetch_key!(@video_codec, codec)
end
