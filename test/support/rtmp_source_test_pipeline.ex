defmodule Membrane.RTMP.Source.Test.Pipeline do
  use Membrane.Pipeline

  alias Membrane.Testing

  import Membrane.ParentSpec

  @impl true
  def handle_init(local_ip: local_ip, port: port, timeout: timeout) do
    Process.register(self(), __MODULE__)

    children = [
      src: %Membrane.RTMP.SourceBin{local_ip: local_ip, port: port, timeout: timeout},
      audio_sink: Testing.Sink,
      video_sink: Testing.Sink
    ]

    links = [
      link(:src) |> via_out(:audio) |> to(:audio_sink),
      link(:src) |> via_out(:video) |> to(:video_sink)
    ]

    {{:ok, [spec: %Membrane.ParentSpec{children: children, links: links}]}, %{}}
  end
end
