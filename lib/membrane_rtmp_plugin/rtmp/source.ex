defmodule Membrane.RTMP.Source do
  @moduledoc """
  This module provides a Membrane Source capable of reading RTMP Streams.

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

  def_options port: [
                spec: 1..65_535,
                description: "Port on which the server will listen"
              ],
              local_ip: [
                spec: binary(),
                default: "127.0.0.1",
                description: "IP address on which the server will listen"
              ],
              timeout: [
                spec: Time.t() | :infinity,
                default: :infinity,
                description: """
                Time during which the connection with the client must be established before handle_prepared_to_playing fails.

                Duration given must be a multiply of one second.
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
    rtmp_address = "rtmp://#{state.local_ip}:#{state.port}"

    with {:ok, native} <- Native.create(rtmp_address, state.timeout),
         :ok <- Native.stream_frames(native) do
      Membrane.Logger.debug("Connection established @ #{rtmp_address}")
      {:ok, %{state | native: native}}
    else
      {:error, reason} ->
        raise("Transition to state playing failed because of: `#{reason}`")
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
    Membrane.Logger.debug("Received end of stream")
    {{:ok, end_of_stream: :output}, state}
  end

  def handle_other(msg, _ctx, state) do
    {:ok, state}
  end
end
