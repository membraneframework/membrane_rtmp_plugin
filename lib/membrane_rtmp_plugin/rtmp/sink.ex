defmodule Membrane.RTMP.Sink do
  @moduledoc """
  Membrane element being client-side of RTMP streams

  Implementation based on FFmpeg
  """
  use Membrane.Sink
  alias Membrane.{AAC}

  def_input_pad :audio,
    availability: :always,
    caps: {AAC, encapsulation: :none},
    mode: :pull,
    demand_unit: :buffers

  def_input_pad :video,
    availability: :always,
    caps: :any,
    mode: :pull,
    demand_unit: :buffers

  def_options rtmp_url: [
                type: :string,
                spec: String.t(),
                description: "URL address of an RTMP/RTMPS stream destination (e.g. youtube)."
              ]

  @impl true
  def handle_init(options) do
    {:ok, Map.from_struct(options)}
  end

  @impl true
  def handle_prepared_to_playing(ctx, state) do
    demands = ctx.pads |> Map.keys() |> Enum.map(&{:demand, &1})
    {{:ok, demands}, state}
  end

  @impl true
  def handle_start_of_stream(_pad, _ctx, state) do
    {:ok, state}
  end

  @impl true
  def handle_end_of_stream(_pad, _ctx, state) do
    {:ok, state}
  end

  @impl true
  def handle_write(pad, _buffer, _ctx, state) do
    {{:ok, demand: pad}, state}
  end
end
