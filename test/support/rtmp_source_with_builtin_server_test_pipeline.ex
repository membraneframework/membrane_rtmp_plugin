defmodule Membrane.RTMP.Source.WithBuiltinServerTestPipeline do
  @moduledoc false
  use Membrane.Pipeline

  alias Membrane.RTMP.SourceBin
  alias Membrane.Testing

  @impl true
  def handle_init(_ctx, %{
        app: app,
        stream_key: stream_key,
        port: port,
        use_ssl?: use_ssl?
      }) do
    protocol = if use_ssl?, do: "rtmps", else: "rtmp"

    structure = [
      child(:src, %SourceBin{
        url: "#{protocol}://localhost:#{port}/#{app}/#{stream_key}"
      }),
      child(:audio_sink, Testing.Sink),
      child(:video_sink, Testing.Sink),
      get_child(:src) |> via_out(:audio) |> get_child(:audio_sink),
      get_child(:src) |> via_out(:video) |> get_child(:video_sink)
    ]

    {[spec: structure], %{}}
  end
end
