defmodule Membrane.RTMP.Source.TestPipeline do
  @moduledoc false
  use Membrane.Pipeline

  alias Membrane.RTMP.SourceBin
  alias Membrane.Testing

  @impl true
  def handle_init(_ctx, %{
        socket: socket,
        test_process: test_process,
        validator: validator,
        use_ssl?: use_ssl?
      }) do
    structure = [
      child(:src, %SourceBin{
        use_ssl?: use_ssl?,
        socket: socket,
        validator: validator
      }),
      child(:audio_sink, Testing.Sink),
      child(:video_sink, Testing.Sink),
      get_child(:src) |> via_out(:audio) |> get_child(:audio_sink),
      get_child(:src) |> via_out(:video) |> get_child(:video_sink)
    ]

    send(test_process, {:pipeline_started, self()})

    {[spec: structure], %{socket: socket}}
  end

  @impl true
  def handle_child_notification(
        {:socket_control_needed, _socket, _source} = notification,
        :src,
        _ctx,
        state
      ) do
    send(self(), notification)

    {[], state}
  end

  def handle_child_notification(_notification, _child, _ctx, state) do
    {[], state}
  end

  @impl true
  def handle_info({:socket_control_needed, socket, source} = notification, _ctx, state) do
    case SourceBin.pass_control(socket, source) do
      :ok ->
        :ok

      {:error, :not_owner} ->
        Process.send_after(self(), notification, 200)
    end

    {[], state}
  end

  @impl true
  def handle_info({:secure_socket_control_needed, socket, source} = notification, _ctx, state) do
    case SourceBin.secure_pass_control(socket, source) do
      :ok ->
        :ok

      {:error, :not_owner} ->
        Process.send_after(self(), notification, 200)
    end

    {[], state}
  end
end
