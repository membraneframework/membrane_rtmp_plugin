defmodule Membrane.RTMP.SourceBin do
  @moduledoc """
  Bin responsible for demuxing and parsing a video stream.

  The bin requires the RTMP client to be already connected.
  Outputs single audio and video which are ready for further processing with Membrane Elements.
  At this moment only AAC and H264 codecs are supported.
  """
  use Membrane.Bin

  alias Membrane.{AAC, H264, RTMP}

  def_output_pad :video,
    caps: H264,
    availability: :always,
    mode: :pull,
    demand_unit: :buffers

  def_output_pad :audio,
    caps: AAC,
    availability: :always,
    mode: :pull,
    demand_unit: :buffers

  def_options socket: [
                spec: port(),
                description:
                  "Socket connected to a client, on which the bin will receive RTMP stream."
              ]

  @impl true
  def handle_init(%__MODULE__{} = options) do
    spec = %ParentSpec{
      children: %{
        src: %RTMP.Source{socket: options.socket},
        demuxer: Membrane.FLV.Demuxer,
        video_parser: %Membrane.H264.FFmpeg.Parser{
          alignment: :au,
          attach_nalus?: true,
          skip_until_keyframe?: true
        },
        audio_parser: %Membrane.AAC.Parser{
          in_encapsulation: :none,
          out_encapsulation: :none
        }
      },
      links: [
        link(:src) |> to(:demuxer),
        #
        link(:demuxer)
        |> via_out(Pad.ref(:audio, 0))
        |> to(:audio_parser)
        |> to_bin_output(:audio),
        #
        link(:demuxer)
        |> via_out(Pad.ref(:video, 0))
        |> to(:video_parser)
        |> to_bin_output(:video)
      ]
    }

    {{:ok, spec: spec}, %{}}
  end

  @impl true
  def handle_notification(
        :rtmp_source_initialized,
        :src,
        %{children: %{src: %{pid: source_pid}}},
        state
      ) do
    {{:ok, [notify: {:rtmp_source_initialized, source_pid}]}, state}
  end
end
