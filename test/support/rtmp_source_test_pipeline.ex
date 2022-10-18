defmodule Membrane.RTMP.Source.TestPipeline do
  @moduledoc false
  use Membrane.Pipeline

  import Membrane.ParentSpec

  alias Membrane.RTMP.SourceBin
  alias Membrane.Testing

  @impl true
  def handle_init(socket: socket, test_process: test_process, verifier: verifier) do
    spec = %Membrane.ParentSpec{
      children: [
        src: %SourceBin{
          socket: socket,
          validator: verifier
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
        {:socket_control_needed, _socket, _source} = notification,
        :src,
        _ctx,
        state
      ) do
    send(self(), notification)

    {:ok, state}
  end

  def handle_notification(_notification, _child, _ctx, state) do
    {:ok, state}
  end

  @impl true
  def handle_other({:socket_control_needed, socket, source} = notification, _ctx, state) do
    case SourceBin.pass_control(socket, source) do
      :ok ->
        :ok

      {:error, :not_owner} ->
        Process.send_after(self(), notification, 200)
    end

    {:ok, state}
  end
end
