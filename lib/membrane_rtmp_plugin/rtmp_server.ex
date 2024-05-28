defmodule Membrane.RTMP.Server do
  @moduledoc """
  A simple RTMP server, which handles each new incoming connection.
  """
  use GenServer

  require Logger

  alias Membrane.RTMP.Server.ClientHandlerBehaviour

  @enforce_keys [:behaviour, :behaviour_options, :port, :use_ssl?, :listen_options]
  defstruct @enforce_keys

  @typedoc """
  Defines options for the RTMP server.
  """
  @type t :: %__MODULE__{
          behaviour: ClientHandlerBehaviour.t(),
          behaviour_options: map(),
          port: :inet.port_number(),
          use_ssl?: boolean(),
          listen_options: any()
        }

  @doc """
  Starts the RTMP server.
  """
  @spec start_link(server_options :: t(), name :: atom()) :: GenServer.on_start()
  def start_link(server_options, name \\ nil) do
    gen_server_opts = if name == nil, do: [], else: [name: name]
    GenServer.start_link(__MODULE__, server_options, gen_server_opts)
  end

  @doc """
  Subscribes for the given app and stream key.
  When a client connects (or has already connected) to the server with given app and stream key,
  the subscriber will be informed.
  """
  @spec subscribe(pid() | atom(), String.t(), String.t()) :: :ok
  def subscribe(server_pid, app, stream_key) do
    GenServer.cast(server_pid, {:subscribe, app, stream_key, self()})
    :ok
  end

  @doc """
  Awaits for the client handler of the connection to which the user has previously subscribed.

  Note: this function call is blocking!
  Note: first you need to call `#{__MODULE__}.subscribe/3` to subscribe
  for a given `app` and `stream_key`.
  """
  @spec subscribe(pid() | atom(), non_neg_integer()) :: {:ok, pid()} | :error
  def await_subscription(server_pid, timeout \\ 5_000) do
    receive do
      {:client_handler, client_handler} -> {:ok, client_handler}
    after
      timeout -> :error
    end
  end

  @doc """
  Returns the port on which the server listens for connection.
  """
  @spec get_port(pid()) :: :inet.port_number()
  def get_port(server_pid) do
    GenServer.call(server_pid, :get_port)
  end

  @impl true
  def init(server_options) do
    pid =
      Task.start_link(Membrane.RTMP.Server.Listener, :run, [
        Map.merge(server_options, %{server: self()})
      ])

    {:ok,
     %{
       subscriptions: %{},
       mapping: %{},
       listener: pid,
       port: nil,
       to_reply: [],
       use_ssl?: server_options.use_ssl?
     }}
  end

  @impl true
  def handle_call(:get_port, from, state) do
    if state.port do
      {:reply, state.port, state}
    else
      {:noreply, %{state | to_reply: [from | state.to_reply]}}
    end
  end

  @impl true
  def handle_cast({:subscribe, app, stream_key, subscriber_pid}, state) do
    state = put_in(state, [:subscriptions, {app, stream_key}], subscriber_pid)
    maybe_send_subscription(app, stream_key, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:register_client, app, stream_key, client_handler_pid}, state) do
    state = put_in(state, [:mapping, {app, stream_key}], client_handler_pid)
    maybe_send_subscription(app, stream_key, state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:port, port}, state) do
    Enum.each(state.to_reply, &GenServer.reply(&1, port))
    {:noreply, %{state | port: port, to_reply: []}}
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
