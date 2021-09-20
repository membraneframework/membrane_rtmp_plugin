defmodule Membrane.RTMP.TestPipeline do
  use Membrane.Pipeline
  require Membrane.Logger

  @impl true
  def handle_init(_opts) do
    spec = %ParentSpec{
      children: %{
        src: %Membrane.File.Source{location: "sample.flv"},
        demuxer: Membrane.FLV.Demuxer,
        audio_sink: %Membrane.File.Sink{location: "output.aac"},

        video_parser: %Membrane.H264.FFmpeg.Parser{skip_until_keyframe?: true, framerate: {30, 1}, alignment: :au},
        video_sink: %Membrane.File.Sink{location: "output.avc"},
      },
      links: [
        link(:src) |> to(:demuxer),
        link(:demuxer) |> via_out(:audio) |> to(:audio_sink),
        link(:demuxer) |> via_out(:video) |> to(:video_parser) |> to(:video_sink)
      ]
    }

    {{:ok, spec: spec}, %{}}
  end
end

{:ok, pid} = Membrane.RTMP.TestPipeline.start_link(%{})
Membrane.RTMP.TestPipeline.play(pid)
Process.sleep(100_000)
