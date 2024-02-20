defmodule Membrane.RTMP.Source do
  @moduledoc """
  Membrane Element for receiving an RTMP stream. Acts as a RTMP Server.

  When initializing, the source sends `t:socket_control_needed_t/0` notification,
  upon which it should be granted the control over the `socket` via `:gen_tcp.controlling_process/2`.

  This implementation is limited to only AAC and H264 streams.
  """
  use Membrane.Source

  require Membrane.Logger

  def_output_pad :output,
    availability: :always,
    accepted_format: Membrane.RemoteStream,
    flow_control: :push

  def_options app: [], stream_key: [], server: []

  @impl true
  def handle_init(_ctx, opts) do
    state = %{app: opts.app, stream_key: opts.stream_key, server: opts.server}
    {[], state}
  end

  @impl true
  def handle_playing(_ctx, state) do
    stream_format = [
      stream_format:
        {:output, %Membrane.RemoteStream{content_format: Membrane.FLV, type: :bytestream}}
    ]

    send(state.server, {:subscribe, state.app, state.stream_key, self()})

    {stream_format, state}
  end

  @impl true
  def handle_terminate_request(_ctx, state) do
    {[terminate: :normal], state}
  end

  @impl true
  def handle_info({:client_handler, client_handler_pid}, _ctx, state) do
    send(client_handler_pid, {:send_me_data, self()})
    {[], state}
  end

  @impl true
  def handle_info({:data, data}, _ctx, state) do
    {[buffer: {:output, %Membrane.Buffer{payload: data}}], state}
  end

  @impl true
  def handle_info(:end_of_stream, _ctx, state) do
    {[end_of_stream: :output], state}
  end
end
