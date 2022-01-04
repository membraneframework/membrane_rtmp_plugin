# Before running this example, don't forget to start the RTMP server
# eg. ffmpeg -re -i test/fixtures/testsrc.flv -f flv -c:v copy -c:a copy rtmp://localhost:5000

Mix.install([
  :membrane_core,
  {:membrane_rtmp_plugin, path: __DIR__ |> Path.join("../") |> Path.expand()},
  :membrane_file_plugin,
  :membrane_mp4_plugin,
  :membrane_flv_plugin,
  {:membrane_aac_plugin, github: "membraneframework/membrane_aac_plugin", branch: "bugfix/960-transform", override: true}
], force: true)

defmodule Example do
  use Membrane.Pipeline

  @server_url "localhost"
  @server_port 5000
  @output_file "received.flv"

  @impl true
  def handle_init(_opts) do
    spec = %ParentSpec{
      children: %{
          source: %Membrane.RTMP.SourceBin{
            local_ip: @server_url,
            port: @server_port
          },
          video_payloader: Membrane.MP4.Payloader.H264,
          muxer: Membrane.FLV.Muxer,
          sink: %Membrane.File.Sink{location: @output_file}
        },
        links: [
          link(:source) |> via_out(:audio) |> via_in(Pad.ref(:audio, 0)) |> to(:muxer),
          link(:source) |> via_out(:video) |> to(:video_payloader) |> via_in(Pad.ref(:video, 0)) |> to(:muxer),
          link(:muxer) |> to(:sink)
        ]
    }

    {{:ok, spec: spec}, %{}}
  end

  # The rest of the module is used for self-termination of the pipeline after processing finishes
  @impl true
  def handle_element_end_of_stream({:sink, _pad}, _ctx, state) do
    Membrane.Pipeline.stop_and_terminate(self())
    {:ok, state}
  end

  @impl true
  def handle_element_end_of_stream(_other, _ctx, state), do: {:ok, state}
end

# Initialize and run the pipeline
{:ok, pid} = Example.start()
:ok = Example.play(pid)

monitor_ref = Process.monitor(pid)

# Wait for the pipeline to terminate
receive do
  {:DOWN, ^monitor_ref, :process, _pid, _reason} ->
    :ok
end
