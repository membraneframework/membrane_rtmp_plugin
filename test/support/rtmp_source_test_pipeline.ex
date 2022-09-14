defmodule Membrane.RTMP.Source.TestPipeline do
  @moduledoc false
  use Membrane.Pipeline

  import Membrane.ParentSpec

  alias Membrane.Testing

  @impl true
  def handle_init(socket: socket, test_process: test_process) do
    Process.register(self(), __MODULE__)

    spec = %Membrane.ParentSpec{
      children: [
        src: %Membrane.RTMP.SourceBin{socket: socket},
        audio_sink: Testing.Sink,
        video_sink: Testing.Sink
      ],
      links: [
        link(:src) |> via_out(:audio) |> to(:audio_sink),
        link(:src) |> via_out(:video) |> to(:video_sink)
      ]
    }

    send(test_process, {:pipeline_started, self()})

    {{:ok, [spec: spec, playback: :playing]}, %{socket: socket}}
  end

  @impl true
  def handle_notification({:rtmp_source_initialized, source}, :src, _ctx, state) do
    send(self(), {:rtmp_source_initialized, source})

    {:ok, state}
  end

  @impl true
  def handle_other({:rtmp_source_initialized, source}, _ctx, state) do
    case :gen_tcp.controlling_process(state.socket, source) do
      :ok ->
        :ok

      {:error, :not_owner} ->
        Process.send_after(self(), {:rtmp_source_initialized, source}, 200)
    end

    {:ok, state}
  end
end
