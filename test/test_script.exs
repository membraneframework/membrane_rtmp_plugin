defmodule Membrane.RTMP.TestPipeline do
  use Membrane.Pipeline
  require Membrane.Logger

  @impl true
  def handle_init(_opts) do
    spec = %ParentSpec{
      children: %{
        src: %Membrane.RTMP.Source{port: 9009},
        demuxer: Membrane.FLV.Demuxer,
        video_parser: %Membrane.H264.FFmpeg.Parser{
          framerate: {30, 1},
          alignment: :au,
          attach_nalus?: true,
          skip_until_keyframe?: true
        },
        audio_parser: Membrane.AAC.Timestamper,
        video_sink: %Membrane.HTTPAdaptiveStream.SinkBin{
          manifest_module: Membrane.HTTPAdaptiveStream.HLS,
          target_window_duration: 20 |> Membrane.Time.seconds(),
          target_segment_duration: 8 |> Membrane.Time.seconds(),
          persist?: false,
          storage: %Membrane.HTTPAdaptiveStream.Storages.FileStorage{directory: "output"}
        },
        video_payloader: Membrane.MP4.Payloader.H264,
        video_cmaf_muxer: %Membrane.MP4.CMAF.Muxer{
          segment_duration: 2 |> Membrane.Time.seconds()
        }
      },
      links: [
        link(:src) |> to(:demuxer),
        link(:demuxer)
        |> via_out(:audio)
        |> to(:audio_parser)
        |> via_in(Pad.ref(:input, :audio), options: [encoding: :AAC])
        |> to(:video_sink),
        link(:demuxer)
        |> via_out(:video)
        |> to(:video_parser)
        |> via_in(Pad.ref(:input, :video), options: [encoding: :H264])
        |> to(:video_sink)
      ]
    }

    {{:ok, spec: spec}, %{}}
  end
end

{:ok, pid} = Membrane.RTMP.TestPipeline.start_link(%{})
Membrane.RTMP.TestPipeline.play(pid)
Process.sleep(10_000_000)
