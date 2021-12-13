Mix.install([
  {:membrane_realtimer_plugin, "~> 0.4.0"},
  {:membrane_file_plugin, "~> 0.6"},
  {:membrane_h264_ffmpeg_plugin, "~> 0.15.0"},
  {:membrane_aac_plugin, "~> 0.11.0"},
  {:membrane_mp4_plugin, github: "membraneframework/membrane_mp4_plugin"},
  {:membrane_rtmp_plugin, path: __DIR__ |> Path.join("..") |> Path.expand()}
])

defmodule Example do
  use Membrane.Pipeline

  @impl true
  def handle_init(options) do
    children = [
      video_source: %Membrane.File.Source{location: options[:video_file_path]},
      video_parser: %Membrane.H264.FFmpeg.Parser{
        framerate: {25, 1},
        alignment: :au,
        attach_nalus?: true,
        skip_until_keyframe?: true
      },
      audio_parser: %Membrane.AAC.Parser{
        out_encapsulation: :none
      },
      audio_source: %Membrane.File.Source{location: options[:audio_file_path]},
      video_realtimer: Membrane.Realtimer,
      audio_realtimer: Membrane.Realtimer,
      video_payloader: Membrane.MP4.Payloader.H264,
      rtmps_sink: %Membrane.RTMP.Sink{rtmp_url: options[:rtmp_url]}
    ]

    links = [
      link(:video_source)
      |> to(:video_parser)
      |> to(:video_realtimer)
      |> to(:video_payloader)
      |> via_in(:video)
      |> to(:rtmps_sink),
      link(:audio_source)
      |> to(:audio_parser)
      |> to(:audio_realtimer)
      |> via_in(:audio)
      |> to(:rtmps_sink)
    ]

    {{:ok, spec: %ParentSpec{children: children, links: links}}, %{}}
  end
end

pipeline_options = %{
  video_file_path: "test/fixtures/bun33s_480x270.h264",
  audio_file_path: "test/fixtures/bun33s.aac",
  rtmp_url: System.get_env("RTMP_URL")
}

ref =
Example.start_link(pipeline_options)
  |> elem(1)
  |> tap(&Membrane.Pipeline.play/1)
  |> then(&Process.monitor/1)

receive do
  {:DOWN, ^ref, :process, _pid, _reason} ->
    :ok
end
