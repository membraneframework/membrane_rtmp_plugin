defmodule Membrane.RTMP do
  use Membrane.Source
  require Membrane.Logger
  alias __MODULE__.Native

  def_output_pad :output,
    availability: :always,
    caps: :any,
    mode: :pull

  @impl true
  def handle_init(_opts) do
    {:ok, %{native: nil}}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    with {:ok, native} <- Native.create("rtmp://127.0.0.1:9009") do
      Membrane.Logger.debug("Connection estabilished")
      {{:ok, redemand: :output}, %{state | native: native}}
    else
      {:error, reason} ->
        Membrane.Logger.error("Connection failed: #{reason}")
        {{:ok, redemand: :output}, state}
    end
  end

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, state) do
    with :ok <- Native.get_frame(state.native) do
      {{:ok, redemand: :output}, state}
    else
      # {:error, "skipping"} -> {{:ok, redemand: :output}, state}
      {:error, _reason} = error -> {error, state}
    end
  end

  @impl true
  def handle_other({:data, data} = msg, _ctx, state) do
    IO.inspect(msg, label: "msg")
    buffer = %Membrane.Buffer{payload: data}
    {{:ok, buffer: {:output, buffer}}, state}
  end

  def handle_other(msg, _ctx, state) do
    IO.inspect(msg, label: "unknown_msg")
    {:ok, state}
  end
end
