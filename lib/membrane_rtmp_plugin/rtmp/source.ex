defmodule Membrane.RTMP.Source.Element do
  @moduledoc """
  Membrane Element being a server-side source of RTMP streams.

  Implementation based on FFmpeg
  """
  use Membrane.Source
  alias __MODULE__.Native
  alias Membrane.{FLV, Time}
  require Membrane.Logger

  def_output_pad :output,
    availability: :always,
    caps: {FLV, mode: :packets},
    mode: :push

  def_options url: [
                spec: binary(),
                description: """
                URL on which the FFmpeg instance will be created
                """
              ],
              timeout: [
                spec: Time.t() | :infinity,
                default: :infinity,
                description: """
                Time during which the connection with the client must be established before handle_prepared_to_playing fails.

                Duration given must be a multiply of one second or atom `:infinity`.
                """
              ]

  @impl true
  def handle_init(%__MODULE__{} = opts) do
    {:ok, Map.from_struct(opts) |> Map.merge(%{native: nil})}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    # Native.create is blocking. Hence, the element will only go from prepared to playing when a new connection is established.
    # This might not be desirable, but unfortunately this is caused by the fact that FFmpeg's create_input_stream is awaiting a new connection from the client before returning.

    with {:ok, native} <- Native.create(state.url, state.timeout),
         :ok <- Native.stream_frames(native) do
      Membrane.Logger.debug("Connection established @ #{state.url}")
      {:ok, %{state | native: native}}
    else
      {:error, reason} ->
        raise("Transition to state `playing` failed because of: `#{reason}`")
    end
  end

  @impl true
  def handle_playing_to_prepared(_ctx, state) do
    if not is_nil(state.native), do: Native.stop_streaming(state.native)
    {:ok, %{state | native: nil}}
  end

  @impl true
  def handle_other({:frame, data}, _ctx, state) do
    buffer = %Membrane.Buffer{payload: data}
    {{:ok, buffer: {:output, buffer}}, state}
  end

  def handle_other(:end_of_stream, _ctx, state) do
    {{:ok, end_of_stream: :output}, state}
  end

  def handle_other(msg, _ctx, state) do
    {:ok, state}
  end
end
