defmodule Membrane.RTMP.Server do
  @moduledoc """
  A simple RTMP server, which handles each new incoming connection.

  When new client connects to the server, it goes into :client_waiting_queue and its RTMP handshake will remanin unfinished.
  Only when pipeline tries to pull data from client, its handshake will be finished, and client will be registered.

  Also when new client connects, optional, annonymous function defined by user is triggered.
  The lambda function is given PID of parent server, app and stream key.
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
          new_client_callback: function() | nil
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
       listener: pid,
       port: nil,
       to_reply: [],
       use_ssl?: server_options.use_ssl?,
       new_client_callback: server_options.new_client_callback
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
  def handle_info({:port, port}, state) do
    Enum.each(state.to_reply, &GenServer.reply(&1, port))
    {:noreply, %{state | port: port, to_reply: []}}
  end
end
