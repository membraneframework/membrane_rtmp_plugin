defmodule Membrane.RTMP.Sink do
  @moduledoc """
  Membrane element being client-side of RTMP streams

  Implementation based on FFmpeg
  """
  use Membrane.Sink
  alias __MODULE__.Native
  alias Membrane.{AAC}
  require Membrane.Logger

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
    case Native.init_connection(state.rtmp_url) do
      {:ok, native_state} ->
        Membrane.Logger.debug("Correctly initialized connection with: #{state.rtmp_url}")
        state = Map.put(state, :native_state, native_state)
        demands = ctx.pads |> Map.keys() |> Enum.map(&{:demand, &1})
        {{:ok, demands}, state}

      {:error, reason} ->
        raise("#{reason}")
    end
  end

  @impl true
  def handle_playing_to_prepared(_ctx, state) do
    Native.close_connection(state.native_state)
    state = Map.delete(state, :native_state)
    {:ok, state}
  end

  @impl true
  def handle_caps(:video, %Membrane.Caps.Video.H264{} = caps, _ctx, state) do
    {frames, seconds} = caps.framerate

    case Native.init_video_stream(state.native_state, caps.width, caps.height, frames, seconds) do
      {:ok, native_state} ->
        Membrane.Logger.debug("Correctly initialized video stream.")
        state = Map.put(state, :native_state, native_state)
        {:ok, state}

      {:error, reason} ->
        raise("#{reason}")
    end
  end

  @impl true
  def handle_caps(_pad, _caps, _ctx, state) do
    {:ok, state}
  end

  @impl true
  def handle_start_of_stream(pad, _ctx, state) do
    {{:ok, demand: pad}, state}
  end

  @impl true
  def handle_end_of_stream(_pad, _ctx, state) do
    {:ok, state}
  end

  @impl true
  def handle_write(:video, _buffer, _ctx, state) do
    {{:ok, demand: :video}, state}
  end

  @impl true
  def handle_write(_pad, _buffer, _ctx, state) do
    {:ok, state}
  end
end
