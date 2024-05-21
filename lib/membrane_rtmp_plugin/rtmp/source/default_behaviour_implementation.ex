defmodule Membrane.RTMP.Source.DefaultBehaviourImplementation do
  @moduledoc """
  An implementation of `Membrane.RTMP.Server.ClienHandlerBehaviour` compatible with the
  `Membrane.RTMP.Source` element.
  """

  @behaviour Membrane.RTMP.Server.ClientHandlerBehaviour

  @impl true
  def handle_init(opts) do
    %{
      source_pid: nil,
      buffered: [],
      app: nil,
      stream_key: nil,
      controlling_process: opts.controlling_process
    }
  end

  @impl true
  def handle_connected(connected_msg, state) do
    %{state | app: connected_msg.app}
  end

  @impl true
  def handle_stream_published(publish_msg, state) do
    state = %{state | stream_key: publish_msg.stream_key}
    send(state.controlling_process, {:client_connected, state.app, state.stream_key})
    state
  end

  @impl true
  def handle_info({:send_me_data, source_pid}, state) do
    buffers_to_send = Enum.reverse(state.buffered)
    state = %{state | source_pid: source_pid, buffered: []}
    Enum.each(buffers_to_send, fn buffer -> send_data(state.source_pid, buffer) end)
    state
  end

  @impl true
  def handle_info(_other, state) do
    state
  end

  @impl true
  def handle_data_available(payload, state) do
    if state.source_pid do
      :ok = send_data(state.source_pid, payload)
      state
    else
      %{state | buffered: [payload | state.buffered]}
    end
  end

  @impl true
  def handle_end_of_stream(state) do
    if state.source_pid != nil, do: send_eos(state.source_pid)
    state
  end

  defp send_data(pid, payload) do
    send(pid, {:data, payload})
    :ok
  end

  defp send_eos(pid) do
    send(pid, :end_of_stream)
    :ok
  end

  def request_for_data(client_handler_pid) do
    send(client_handler_pid, {:send_me_data, self()})
    :ok
  end
end