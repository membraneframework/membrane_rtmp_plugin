# Before running this example, make sure that target RTMP server is live.
# If you are streaming to eg. Youtube, you don't need to worry about it.
# If you want to test it locally, you can run the FFmpeg server with:
# ffmpeg -y -listen 1 -f flv -i rtmp://localhost:1935 -c copy dest.flv

Logger.configure(level: :info)

Mix.install([
  :membrane_realtimer_plugin,
  :membrane_hackney_plugin,
  :membrane_h264_plugin,
  {:membrane_rtmp_plugin, path: __DIR__ |> Path.join("..") |> Path.expand()}
])

defmodule Example do
  use Membrane.Pipeline

  @video_url "https://raw.githubusercontent.com/membraneframework/static/gh-pages/samples/big-buck-bunny/bun33s_480x270.h264"

  @impl true
  def handle_init(_ctx, destination: destination) do
    structure = [
      child(:video_source, %Membrane.Hackney.Source{
        location: @video_url,
        hackney_opts: [follow_redirect: true]
      })
      |> child(:video_parser, %Membrane.H264.Parser{
        output_stream_structure: :avc3,
        generate_best_effort_timestamps: %{framerate: {25, 1}}
      })
      |> child(:video_realtimer, Membrane.Realtimer)
      |> via_in(Pad.ref(:video, 0))
      |> child(:rtmp_sink, %Membrane.RTMP.Sink{rtmp_url: destination, tracks: [:video]})
    ]

    {[spec: structure], %{}}
  end

  # The rest of the example module is only used for self-termination of the pipeline after processing finishes
  @impl true
  def handle_element_end_of_stream(:rtmp_sink, _pad, _ctx, state) do
    {[terminate: :normal], state}
  end

  @impl true
  def handle_element_end_of_stream(_child, _pad, _ctx, state) do
    {[], state}
  end
end

destination = System.get_env("RTMP_URL", "rtmp://localhost:1935")

# Initialize the pipeline and start it
{:ok, _supervisor, pipeline} = Example.start_link(destination: destination)

monitor_ref = Process.monitor(pipeline)

# Wait for the pipeline to finish
receive do
  {:DOWN, ^monitor_ref, :process, _pid, _reason} ->
    :ok
end
