defmodule Membrane.RTMP do
  use Membrane.Source
  alias __MODULE__.Native
  require Membrane.Logger

  def_output_pad :output,
    availability: :always,
    caps: :any,
    mode: :push

  @impl true
  def handle_init(_opts) do
    {:ok, %{native: nil}}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    with {:ok, native} <- Native.create("rtmp://127.0.0.1:9009"),
         :ok <- Native.stream_frames(native) do
      Membrane.Logger.debug("Connection estabilished")
      {:ok, %{state | native: native}}
    else
      {:error, reason} ->
        Membrane.Logger.error("Connection failed: #{reason}")
        {{:error, reason}, state}
    end
  end

  @impl true
  def handle_playing_to_prepared(_ctx, state) do
    Native.stop_streaming(state.native)
    {:ok, %{state | native: nil}}
  end

  @impl true
  def handle_other({:frame, data}, _ctx, state) do
    buffer = %Membrane.Buffer{payload: data}
    {{:ok, buffer: {:output, buffer}}, state}
  end

  def handle_other(:end_of_stream, _ctx, state) do
    Membrane.Logger.debug("Received end of stream")
    {{:ok, end_of_stream: :output}, state}
  end

  def handle_other(msg, _ctx, state) do
    {:ok, state}
  end
end
