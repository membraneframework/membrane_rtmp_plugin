# After running this script, you can access the server at rtmp://localhost:1935
# You can use FFmpeg to stream to it
# ffmpeg -re -i test/fixtures/testsrc.flv -f flv -c:v copy -c:a copy rtmp://localhost:1935/app/stream_key

defmodule Pipeline do
  use Membrane.Pipeline

  @output_file "received.flv"

  @impl true
  def handle_init(_ctx, opts) do
    structure = [
      child(:source, %Membrane.RTMP.SourceBin{
        client_ref: opts[:client_ref]
      })
      |> via_out(:audio)
      |> child(:audio_parser, %Membrane.AAC.Parser{
        out_encapsulation: :none,
        output_config: :audio_specific_config
      })
      |> via_in(Pad.ref(:audio, 0))
      |> child(:muxer, Membrane.FLV.Muxer)
      |> child(:sink, %Membrane.File.Sink{location: @output_file}),
      get_child(:source)
      |> via_out(:video)
      |> child(:video_parser, %Membrane.H264.Parser{
        output_stream_structure: :avc1
      })
      |> via_in(Pad.ref(:video, 0))
      |> get_child(:muxer)
    ]

    {[spec: structure], %{}}
  end

  # The rest of the module is used for self-termination of the pipeline after processing finishes
  @impl true
  def handle_element_end_of_stream(:sink, _pad, _ctx, state) do
    {[terminate: :normal], state}
  end

  @impl true
  def handle_element_end_of_stream(_child, _pad, _ctx, state) do
    {[], state}
  end
end

# The client will connect on `rtmp://localhost:1935/app/stream_key`
port = 1935
app = "app"
stream_key = "stream_key"

lambda = fn app, stream_key ->
  IO.inspect("lambda #{app} #{stream_key}")
end

# Run the standalone server
{:ok, server} =
  Membrane.RTMP.Server.start_link(
    handler: %Membrane.RTMP.Source.ClientHandler{controlling_process: self()},
    port: port,
    use_ssl?: false,
    lambda: lambda
  )

# Subscribe to receive client reference that connected to the
# server with given app id and stream key

Enum.each(3..1, fn x ->
  IO.puts(x)
  :timer.sleep(1000)
end)

:ok = Membrane.RTMP.Server.subscribe_any(server)
# Wait for the client reference
{:ok, client_ref} = Membrane.RTMP.Server.await_client_ref(app, stream_key)
# Start the pipeline and provide it with the client_ref
{:ok, _supervisor, pipeline} =
  Membrane.Pipeline.start_link(Pipeline, client_ref: client_ref)

# Wait for the pipeline to terminate itself
ref = Process.monitor(pipeline)

:ok =
  receive do
    {:DOWN, ^ref, _process, ^pipeline, :normal} -> :ok
  end

# Terminate the server
Process.exit(server, :normal)
