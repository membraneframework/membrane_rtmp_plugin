defmodule Membrane.RTMP.Server do
  @moduledoc """
  A simple RTMP server, which handles each new incoming connection. When a new client connects, the new_client_callback is invoked.
  New connections remain in an incomplete RTMP handshake state until another process makes demand for dara data.
  If no data is demanded within the client_timeout period, the connection is closed.

  Options:
   - client_timeout: Time (ms) after which an unused connection is automatically closed.
   - new_client_callback: An anonymous function called when a new client connects.
      It receives the client reference, app and stream_key, allowing custom processing,
      like sending the reference to another process.
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
          new_client_callback:
            (client_ref :: pid(), app :: String.t(), stream_key :: String.t() -> any()),
          client_timeout: non_neg_integer()
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
  def handle_info({:port, port}, state) do
    Enum.each(state.to_reply, &GenServer.reply(&1, port))
    {:noreply, %{state | port: port, to_reply: []}}
  end
end
