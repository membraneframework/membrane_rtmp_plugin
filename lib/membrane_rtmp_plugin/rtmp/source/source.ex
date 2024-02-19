defmodule Membrane.RTMP.Source do
  @moduledoc """
  Membrane Element for receiving an RTMP stream. Acts as a RTMP Server.

  When initializing, the source sends `t:socket_control_needed_t/0` notification,
  upon which it should be granted the control over the `socket` via `:gen_tcp.controlling_process/2`.

  This implementation is limited to only AAC and H264 streams.
  """
  use Membrane.Source

  require Membrane.Logger

  alias Membrane.RTMP.{Handshake, MessageHandler, MessageParser}

  def_output_pad :output,
    availability: :always,
    accepted_format: Membrane.RemoteStream,
    flow_control: :push

  def_options app: [], stream_key: [], client_resolver: []

  @typedoc """
  Notification sent when the RTMP Source element is initialized and it should be granted control over the socket using `:gen_tcp.controlling_process/2`.
  """
  @type socket_control_needed_t() :: {:socket_control_needed, :gen_tcp.socket(), pid()}

  @typedoc """
  Same as `t:socket_control_needed_t/0` but for secured socket meant for RTMPS.
  """
  @type ssl_socket_control_needed_t() :: {:ssl_socket_control_needed, :ssl.sslsocket(), pid()}

  @typedoc """
  Notification sent when the socket has been closed but no media data has flown through it.

  This notification is only sent when the `:output` pad never reaches `:start_of_stream`.
  """
  @type unexpected_socket_closed_t() :: :unexpected_socket_closed

  @impl true
  def handle_init(_ctx, opts) do
    state = %{app: opts.app, stream_key: opts.stream_key, client_resolver: opts.client_resolver}
    {[], state}
  end

  @impl true
  def handle_playing(_ctx, state) do
    stream_format = [
      stream_format:
        {:output, %Membrane.RemoteStream{content_format: Membrane.FLV, type: :bytestream}}
    ]

    subscribe(state)

    {stream_format, state}
  end

  defp subscribe(state) do
    send(state.client_resolver, {:subscribe, state.app, state.stream_key, self()})
  end

  @impl true
  def handle_terminate_request(_ctx, state) do
    {[terminate: :normal], state}
  end

  @impl true
  def handle_info({:data, data}, _ctx, state) do
    {[buffer: {:output, %Membrane.Buffer{payload: data}}], state}
  end
end
