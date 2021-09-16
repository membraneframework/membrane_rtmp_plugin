defmodule Membrane.RTMP.TestPipeline do
  use Membrane.Pipeline
  require Membrane.Logger

  @impl true
  def handle_init(_opts) do
    spec = %ParentSpec{
      children: %{
        src: Membrane.RTMP,
        sink: %Membrane.File.Sink{location: "output.flv"}
      },
      links: [
        link(:src) |> to(:sink)
      ]
    }

    {{:ok, spec: spec}, %{}}
  end
end

{:ok, pid} = Membrane.RTMP.TestPipeline.start_link(%{})
Membrane.RTMP.TestPipeline.play(pid)
Process.sleep(100_000)
