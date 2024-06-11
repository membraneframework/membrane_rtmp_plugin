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
        client_handler: opts[:client_handler]
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

    {[spec: structure], %{controller_pid: opts[:controller_pid]}}
  end

  # The rest of the module is used for self-termination of the pipeline after processing finishes
  @impl true
  def handle_element_end_of_stream(:sink, _pad, _ctx, state) do
    send(state.controller_pid, :eos)
    {[terminate: :normal], state}
  end

  @impl true
  def handle_element_end_of_stream(_child, _pad, _ctx, state) do
    {[], state}
  end
end

# Run the standalone server
{:ok, server} =
  Membrane.RTMP.Server.start_link(
    behaviour: %Membrane.RTMP.Source.ClientHandler{controlling_process: self()},
    port: 1935,
    use_ssl?: false
  )

# Subscribe to receive client handler that connected to the
# server with given app id and stream key
:ok = Membrane.RTMP.Server.subscribe(server, "app", "stream_key")

# Wait for the client handler
client_handler =
  receive do
    {:client_handler, client_handler} ->
      client_handler
  end

# Start the pipeline and provide it with the client_handler

{:ok, _supervisor, pipeline} =
  Membrane.Pipeline.start_link(Pipeline, client_handler: client_handler, controller_pid: self())

# Wait for end of stream
:ok =
  receive do
    :eos -> :ok
  end

# Terminate the server
Process.exit(server, :normal)

# Terminate the pipeline
:ok = Membrane.Pipeline.terminate(pipeline)
