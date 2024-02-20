defmodule Membrane.RTMP.Source.TestPipeline do
  @moduledoc false
  use Membrane.Pipeline

  alias Membrane.RTMP.SourceBin
  alias Membrane.Testing

  @impl true
  def handle_setup(_ctx, %{
        app: app,
        stream_key: stream_key,
        server: server
      }) do
    structure = [
      child(:src, %SourceBin{
        app: app,
        stream_key: stream_key,
        server: server
      }),
      child(:audio_sink, Testing.Sink),
      child(:video_sink, Testing.Sink),
      get_child(:src) |> via_out(:audio) |> get_child(:audio_sink),
      get_child(:src) |> via_out(:video) |> get_child(:video_sink)
    ]

    {[spec: structure], %{}}
  end
end
