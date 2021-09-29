defmodule Membrane.RTMP.TestPipeline do
  use Membrane.Pipeline
  require Membrane.Logger

  @impl true
  def handle_init(_opts) do
    spec = %ParentSpec{
      children: %{
        src: %Membrane.RTMP.SourceBin{port: 9009},
        sink: %Membrane.HTTPAdaptiveStream.SinkBin{
          manifest_module: Membrane.HTTPAdaptiveStream.HLS,
          target_window_duration: 20 |> Membrane.Time.seconds(),
          target_segment_duration: 8 |> Membrane.Time.seconds(),
          persist?: false,
          storage: %Membrane.HTTPAdaptiveStream.Storages.FileStorage{directory: "output"}
        }
      },
      links: [
        link(:src)
        |> via_out(:audio)
        |> via_in(Pad.ref(:input, :audio), options: [encoding: :AAC])
        |> to(:sink),
        link(:src)
        |> via_out(:video)
        |> via_in(Pad.ref(:input, :video), options: [encoding: :H264])
        |> to(:sink)
      ]
    }

    {{:ok, spec: spec}, %{}}
  end
end

{:ok, pid} = Membrane.RTMP.TestPipeline.start_link(%{})
Membrane.RTMP.TestPipeline.play(pid)
Process.sleep(10_000_000)
