defmodule Membrane.RTMP.Source.TestPipeline do
  @moduledoc false
  use Membrane.Pipeline

  alias Membrane.RTMP.SourceBin
  alias Membrane.Testing

  @impl true
  def handle_init(_ctx, %{
        app: app,
        stream_key: stream_key,
        port: port
      }) do
    structure = [
      child(:src, %SourceBin{
        url: "rtmp://localhost:#{port}/#{app}/#{stream_key}"
      }),
      child(:audio_sink, Testing.Sink),
      child(:video_sink, Testing.Sink),
      get_child(:src) |> via_out(:audio) |> get_child(:audio_sink),
      get_child(:src) |> via_out(:video) |> get_child(:video_sink)
    ]

    {[spec: structure], %{}}
  end
end
