# Before running this example, make sure that target RTMP server is live.
# If you are streaming to eg. Youtube, you don't need to worry about it.
# If you want to test it locally, you can run the FFmpeg server with:
# ffmpeg -listen 1 -f flv -i rtmp://localhost:1935 -c copy dest.flv

Mix.install([
  {:membrane_core, "~> 0.10.1"},
  {:membrane_rtmp_plugin, path: __DIR__ |> Path.join("..") |> Path.expand()},
  :membrane_realtimer_plugin,
  :membrane_hackney_plugin,
  :membrane_h264_ffmpeg_plugin,
  :membrane_aac_plugin,
  :membrane_mp4_plugin
])

defmodule Example do
  use Membrane.Pipeline

  @impl true
  def handle_init(_opts) do
    children = [
      video_source: %Membrane.Hackney.Source{
        location: "https://raw.githubusercontent.com/membraneframework/static/gh-pages/samples/big-buck-bunny/bun33s_480x270.h264",
        hackney_opts: [follow_redirect: true]
      },
      video_parser: %Membrane.H264.FFmpeg.Parser{
        framerate: {25, 1},
        alignment: :au,
        attach_nalus?: true,
        skip_until_keyframe?: true
      },
      audio_parser: %Membrane.AAC.Parser{
        in_encapsulation: :ADTS,
        out_encapsulation: :none
      },
      audio_source: %Membrane.Hackney.Source{
        location: "https://raw.githubusercontent.com/membraneframework/static/gh-pages/samples/big-buck-bunny/bun33s.aac",
        hackney_opts: [follow_redirect: true]
      },
      video_realtimer: Membrane.Realtimer,
      audio_realtimer: Membrane.Realtimer,
      video_payloader: Membrane.MP4.Payloader.H264,
      rtmp_sink: %Membrane.RTMP.Sink{rtmp_url: System.get_env("RTMP_URL", "rtmp://localhost:1935")}
    ]

    links = [
      link(:video_source)
      |> to(:video_parser)
      |> to(:video_realtimer)
      |> to(:video_payloader)
      |> via_in(:video)
      |> to(:rtmp_sink),
      link(:audio_source)
      |> to(:audio_parser)
      |> to(:audio_realtimer)
      |> via_in(:audio)
      |> to(:rtmp_sink)
    ]

    {{:ok, spec: %ParentSpec{children: children, links: links}, playback: :playing}, %{finished_streams: []}}
  end

  # The rest of the example module is only used for self-termination of the pipeline after processing finishes
  @impl true
  def handle_element_end_of_stream({:rtmp_sink, pad}, _ctx, state) when length(state.finished_streams) == 1 do
    Membrane.Pipeline.terminate(self())
    {:ok, Map.put(state, :finished_streams, &[pad | &1])}
  end

  @impl true
  def handle_element_end_of_stream({:rtmp_sink, pad}, _ctx, state) do
    {:ok, Map.put(state, :finished_streams, [pad])}
  end

  @impl true
  def handle_element_end_of_stream(_element, _ctx, state) do
    {:ok, state}
  end
end

# Initialize the pipeline and start it
{:ok, pipeline} = Example.start_link()

monitor_ref = Process.monitor(pipeline)

# Wait for the pipeline to finish
receive do
  {:DOWN, ^monitor_ref, :process, _pid, _reason} ->
    :ok
end
