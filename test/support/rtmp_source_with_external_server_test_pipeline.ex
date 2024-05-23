defmodule Membrane.RTMP.Source.WithExternalServerTestPipeline do
  @moduledoc false
  use Membrane.Pipeline

  alias Membrane.RTMP.SourceBin
  alias Membrane.Testing

  @impl true
  def handle_init(_ctx, %{
        client_handler: client_handler
      }) do
    structure = [
      child(:src, %SourceBin{
        client_handler: client_handler
      }),
      child(:audio_sink, Testing.Sink),
      child(:video_sink, Testing.Sink),
      get_child(:src)
      |> via_out(:audio)
      |> get_child(:audio_sink),
      get_child(:src) |> via_out(:video) |> get_child(:video_sink)
    ]

    {[spec: structure], %{}}
  end
end
