defmodule Membrane.RTMP.Server do
  @moduledoc """
  A simple RTMP server, which handles each new incoming connection.
  """
  use GenServer

  require Logger

  alias Membrane.RTMP.Server.ClientHandlerBehaviour

  @typedoc """
  Defines options for the RTMP server.
  """
  @type t :: [
          handler: ClientHandlerBehaviour.t(),
          port: :inet.port_number(),
          use_ssl?: boolean(),
          name: atom() | nil,
          lambda: function() | nil
        ]

  @type server_identifier :: pid() | atom()

  @doc """
  Starts the RTMP server.
  """
  @spec start_link(server_options :: t()) :: GenServer.on_start()
  def start_link(server_options) do
    gen_server_opts = if server_options[:name] == nil, do: [], else: [name: server_options[:name]]
    server_options = Enum.into(server_options, %{})
    GenServer.start_link(__MODULE__, server_options, gen_server_opts)
  end

  @doc """
  Subscribes for any app/stream_key.
  When a new client connects, subscriber will be informed, if currently is awaiting client_ref for a given app/stream_key
  """
  @spec subscribe_any(server_identifier()) :: :ok
  def subscribe_any(server_identifier) do
    GenServer.cast(server_identifier, {:subscribe_any, self()})
    :ok
  end

  @doc """
  Awaits for the client reference of the connection to specified app/stream_key

  Note: this function call is blocking!
  Note: first you need to call `#{__MODULE__}.subscribe_any/1`.
  """
  @spec await_client_ref(String.t(), String.t(), non_neg_integer()) :: {:ok, pid()} | :error
  def await_client_ref(app, stream_key, timeout \\ 5_000) do
    receive do
      {:client_ref, client_ref, ^app, ^stream_key} ->
        {:ok, client_ref}
    after
      timeout -> :error
    end
  end

  @doc """
  Returns the port on which the server listens for connection.
  """
  @spec get_port(server_identifier()) :: :inet.port_number()
  def get_port(server_identifier) do
    GenServer.call(server_identifier, :get_port)
  end

  @impl true
  def init(server_options) do
    pid =
      Task.start_link(Membrane.RTMP.Server.Listener, :run, [
        Map.merge(server_options, %{server: self()})
      ])

    {:ok,
     %{
       subscriptions_any: [],
       client_reference_mapping: %{},
       client_waiting_queue: %{},
       listener: pid,
       port: nil,
       to_reply: [],
       use_ssl?: server_options.use_ssl?,
       lambda: server_options.lambda
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
  def handle_cast({:subscribe_any, subscriber_pid}, state) do
    subs = [state.subscriptions_any ++ subscriber_pid]
    state = %{state | subscriptions_any: subs}

    # try to send all client_refs from :client_waiting_queue to this subscriber, maybe is awaiting one of /app/stream_keys
    state.client_waiting_queue
    |> Enum.each(fn {{app, stream_key}, client_ref} ->
      send(subscriber_pid, {:client_ref, client_ref, app, stream_key})
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:register_client, app, stream_key, client_reference_pid}, state) do
    state = put_in(state, [:client_reference_mapping, {app, stream_key}], client_reference_pid)
    client_waiting_queue = state.client_waiting_queue |> Map.delete({app, stream_key})
    {:noreply, %{state | client_waiting_queue: client_waiting_queue}}
  end

  @impl true
  def handle_info({:register_client_in_queue, app, stream_key, client_ref}, state) do
    if is_function(state.lambda) do
      state.lambda.(self(), app, stream_key)
    end

    state = put_in(state, [:client_waiting_queue, {app, stream_key}], client_ref)
    # send client ref_to anyone possibly awaiting it
    state.subscriptions_any
    |> Enum.each(fn subscriber -> send(subscriber, {:client_ref, client_ref, app, stream_key}) end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:port, port}, state) do
    Enum.each(state.to_reply, &GenServer.reply(&1, port))
    {:noreply, %{state | port: port, to_reply: []}}
  end

  @impl true
  def handle_info({:lambda, message}, state) do
    IO.inspect(message, label: "message")
    {:noreply, state}
  end
end
