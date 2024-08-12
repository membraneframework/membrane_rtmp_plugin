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

# example lambda function that upon launching will send client reference back to parent process.
parent_process_pid = self()

handle_new_client = fn client_ref, app, stream_key ->
  send(parent_process_pid, {:client_ref, client_ref, app, stream_key})
end

# Run the standalone server
{:ok, server} =
  Membrane.RTMPServer.start_link(
    handler: %Membrane.RTMP.Source.ClientHandlerImpl{controlling_process: self()},
    port: port,
    use_ssl?: false,
    handle_new_client: handle_new_client,
    client_timeout: 5_000
  )

app = "app"
stream_key = "stream_key"

# Wait max 10s for client to connect on /app/stream_key
{:ok, client_ref} =
  receive do
    {:client_ref, client_ref, ^app, ^stream_key} ->
      {:ok, client_ref}
  after
    10_000 -> :timeout
  end

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
