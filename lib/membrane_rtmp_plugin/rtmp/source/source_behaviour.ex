defmodule Membrane.RTMP.Source.Behaviour do
  @moduledoc """
  An implementation of `Membrane.RTMP.Server.ClienHandlerBehaviour` compatible with the
  `Membrane.RTMP.Source` element.
  """

  @behaviour Membrane.RTMP.Server.ClientHandlerBehaviour

  @impl true
  def handle_init() do
    %{source_pid: nil, buffered: [], app: nil, stream_key: nil}
  end

  @impl true
  def handle_end_of_stream(state) do
    if state.source_pid != nil, do: send(state.source_pid, :end_of_stream)
    state
  end

  @impl true
  def handle_data_available(payload, state) do
    if state.source_pid do
      send(state.source_pid, {:data, payload})
      state
    else
      %{state | buffered: [payload | state.buffered]}
    end
  end

  @impl true
  def handle_connected(connected_msg, state) do
    %{state | app: connected_msg.app}
  end

  @impl true
  def handle_info({:send_me_data, source_pid}, state) do
    buffers_to_send = Enum.reverse(state.buffered)
    state = %{state | source_pid: source_pid, buffered: []}
    Enum.each(buffers_to_send, fn buffer -> send(state.source_pid, {:data, buffer}) end)
    state
  end

  @impl true
  def handle_info(_other, state) do
    state
  end

  @impl true
  def handle_stream_published(publish_msg, state) do
    %{state | stream_key: publish_msg.stream_key}
  end
end
