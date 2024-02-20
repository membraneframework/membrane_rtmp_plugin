defmodule Membrane.RTMP.Server do
  @moduledoc """
  A simple RTMP server, which handles each new incoming connection.
  """

  use GenServer

  require Logger

  alias Membrane.RTMP.Server.ClientHandler
  @enforce_keys [:port, :behaviour, :tcp_listener]

  defstruct @enforce_keys

  @typedoc """
  Defines options for the RTMP server.
  """
  @type t :: %__MODULE__{
          port: :inet.port_number(),
          behaviour: Membrane.RTMP.Server.Behaviour.t(),
          tcp_listener: pid()
        }

  @spec init(
          port: :inet.port_number(),
          behaviour: Membrane.RTMP.Server.Behaviour.t(),
          use_ssl?: boolean(),
          listen_options: term()
        ) :: {:ok, pid}
  def init(port: port, behaviour: behaviour, use_ssl?: use_ssl?, listen_options: listen_options) do
    pid =
      Task.start_link(Membrane.RTMP.Server.Listener, :run, [
        port,
        behaviour,
        self(),
        use_ssl?,
        listen_options
      ])

    {:ok,
     %{
       subscriptions: %{},
       mapping: %{},
       tcp_listener: pid,
       port: nil,
       to_reply: [],
       use_ssl?: use_ssl?
     }}
  end

  @impl true
  def handle_info({:register_client, app, stream_key, client_handler_pid}, state) do
    state = put_in(state, [:mapping, {app, stream_key}], client_handler_pid)
    maybe_send_subscription(app, stream_key, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:subscribe, app, stream_key, subscriber_pid}, state) do
    state = put_in(state, [:subscriptions, {app, stream_key}], subscriber_pid)
    maybe_send_subscription(app, stream_key, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:port, port}, state) do
    Enum.each(state.to_reply, &GenServer.reply(&1, port))
    {:noreply, %{state | port: port, to_reply: []}}
  end

  @impl true
  def handle_call(:get_port, from, state) do
    if state.port do
      {:reply, state.port, state}
    else
      {:noreply, %{state | to_reply: [from | state.to_reply]}}
    end
  end

  defp maybe_send_subscription(app, stream_key, state) do
    if state.subscriptions[{app, stream_key}] != nil and state.mapping[{app, stream_key}] != nil do
      send(
        state.subscriptions[{app, stream_key}],
        {:client_handler, state.mapping[{app, stream_key}]}
      )
    end
  end
end
