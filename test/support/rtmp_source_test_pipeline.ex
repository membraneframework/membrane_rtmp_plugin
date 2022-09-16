defmodule Membrane.RTMP.Source.TestPipeline do
  @moduledoc false
  use Membrane.Pipeline

  import Membrane.ParentSpec

  alias Membrane.RTMP.SourceBin
  alias Membrane.Testing

  @impl true
  def handle_init(socket: socket, test_process: test_process) do
    spec = %Membrane.ParentSpec{
      children: [
        src: %SourceBin{
          socket: socket,
          validator: Membrane.RTMP.Source.TestValidator
        },
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
  def handle_notification(
        {:rtmp_source_initialized, _socket, _source} = notification,
        :src,
        _ctx,
        state
      ) do
    send(self(), notification)

    {:ok, state}
  end

  @impl true
  def handle_other({:rtmp_source_initialized, socket, source} = notification, _ctx, state) do
    case SourceBin.pass_control(socket, source) do
      :ok ->
        :ok

      {:error, :not_owner} ->
        Process.send_after(self(), notification, 200)
    end

    {:ok, state}
  end
end
