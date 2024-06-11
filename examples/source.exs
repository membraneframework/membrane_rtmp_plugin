# After running this script, you can access the server at rtmp://localhost:5000
# You can use FFmpeg to stream to it
# ffmpeg -re -i test/fixtures/testsrc.flv -f flv -c:v copy -c:a copy rtmp://localhost:5000

Mix.install([
  :membrane_aac_plugin,
  :membrane_h264_plugin,
  :membrane_flv_plugin,
  :membrane_file_plugin,
  {:membrane_rtmp_plugin, path: __DIR__ |> Path.join("..") |> Path.expand()}
])

defmodule Pipeline do
  use Membrane.Pipeline

  @output_file "received.flv"

  @impl true
  def handle_init(_ctx, opts) do
    structure = [
      child(:source, %Membrane.RTMP.SourceBin{
        url: "rtmp://127.0.0.1:1935/app/stream_key"
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

{:ok, _supervisor, _pipeline} = Membrane.Pipeline.start_link(Pipeline, controller_pid: self())

:ok =
  receive do
    :eos -> :ok
  end
