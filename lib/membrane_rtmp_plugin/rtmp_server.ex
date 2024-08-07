defmodule Membrane.RTMP.Server do
  @moduledoc """
  A simple RTMP server, which handles each new incoming connection. When a new client connects, the `handle_new_client` is invoked.
  New connections remain in an incomplete RTMP handshake state, until another process makes demand for their data.
  If no data is demanded within the client_timeout period, TCP socket is closed.

  Options:
   - client_timeout: Time (ms) after which an unused client connection is automatically closed.
   - handle_new_client: An anonymous function called when a new client connects.
      It receives the client reference, `app` and `stream_key`, allowing custom processing,
      like sending the reference to another process. If it's not provided, default implementation is used:
      {:client_ref, client_ref, app, stream_key} message is sent to the process that invoked RTMP.Server.start_link().
  """
  use GenServer

  require Logger

  alias Membrane.RTMP.Server.ClientHandler

  @typedoc """
  Defines options for the RTMP server.
  """
  @type t :: [
          handler: ClientHandler.t(),
          port: :inet.port_number(),
          use_ssl?: boolean(),
          name: atom() | nil,
          handle_new_client:
            (client_ref :: pid(), app :: String.t(), stream_key :: String.t() ->
               any())
            | nil,
          client_timeout: Membrane.Time.t()
        ]

  @type server_identifier :: pid() | atom()

  @doc """
  Starts the RTMP server.
  """
  @spec start_link(server_options :: t()) :: GenServer.on_start()
  def start_link(server_options) do
    gen_server_opts = if server_options[:name] == nil, do: [], else: [name: server_options[:name]]

    server_options = Enum.into(server_options, %{})

    server_options =
      if server_options[:handle_new_client] == nil do
        parent_process_pid = self()

        callback = fn client_ref, app, stream_key ->
          send(parent_process_pid, {:client_ref, client_ref, app, stream_key})
        end

        Map.put(server_options, :handle_new_client, callback)
      else
        server_options
      end

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

  @doc """
  Extracts ssl, port, app and stream_key from url.
  """
  @spec parse_url(url :: String.t()) :: {boolean(), integer(), String.t(), String.t()}
  def parse_url(url) do
    uri = URI.parse(url)
    port = uri.port

    {app, stream_key} =
      case (uri.path || "")
           |> String.trim_leading("/")
           |> String.trim_trailing("/")
           |> String.split("/") do
        [app, stream_key] -> {app, stream_key}
        [app] -> {app, ""}
      end

    use_ssl? =
      case uri.scheme do
        "rtmp" -> false
        "rtmps" -> true
      end

    {use_ssl?, port, app, stream_key}
  end
end
