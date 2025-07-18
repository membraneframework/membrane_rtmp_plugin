defmodule Membrane.RTMPServer do
  @moduledoc """
  A simple RTMP server, which handles each new incoming connection. When a new client connects, the `handle_new_client` is invoked.
  New connections remain in an incomplete RTMP handshake state, until another process makes demand for their data.
  If no data is demanded within the client_timeout period, TCP socket is closed.

  Options:
  - handle_new_client: An anonymous function called when a new client connects.
      It receives the client reference, `app` and `stream_key`, allowing custom processing,
      like sending the reference to another process. The function should return a `t:#{inspect(__MODULE__)}.client_behaviour_spec/0`
      which defines how the client should behave.
  - port: Port on which RTMP server will listen. Defaults to 1935.
  - use_ssl?: If true, SSL socket (for RTMPS) will be used. Otherwise, TCP socket (for RTMP) will be used. Defaults to false.
  - ssl_options: SSL options to configure the SSL socket.
  - client_timeout: Time after which an unused client connection is automatically closed, expressed in `Membrane.Time.t()` units. Defaults to 5 seconds.
  - name: If not nil, value of this field will be used as a name under which the server's process will be registered. Defaults to nil.

  ## SSL Configuration

  SSL options can be configured at the application level or passed as runtime options.

  ### Application Configuration

      config :membrane_rtmp_plugin, :ssl,
        certfile: "/path/to/cert.pem",
        keyfile: "/path/to/key.pem",
        verify: :verify_none,
        fail_if_no_peer_cert: false,
        versions: [:"tlsv1.2", :"tlsv1.3"]

  ### Runtime Options

      Membrane.RTMPServer.start_link(
        port: 1935,
        use_ssl?: true,
        ssl_options: [
          certfile: "/path/to/cert.pem",
          keyfile: "/path/to/key.pem"
        ],
        handle_new_client: &my_handler/3
      )
  """
  use GenServer

  require Logger

  alias Membrane.RTMPServer.ClientHandler

  @typedoc """
  Defines options for the RTMP server.
  """
  @type t :: [
          port: :inet.port_number(),
          use_ssl?: boolean(),
          ssl_options: keyword() | nil,
          name: atom() | nil,
          handle_new_client: (client_ref :: pid(), app :: String.t(), stream_key :: String.t() ->
                                client_behaviour_spec()),
          client_timeout: Membrane.Time.t()
        ]

  @default_options %{
    port: 1935,
    use_ssl?: false,
    ssl_options: nil,
    name: nil,
    client_timeout: Membrane.Time.seconds(5)
  }

  @typedoc """
  A type representing how a client handler should behave.
  If just a tuple is passed, the second element of that tuple is used as
  an input argument of the `c:#{inspect(ClientHandler)}.handle_init/1`. Otherwise, an empty
  map is passed to the `c:#{inspect(ClientHandler)}.handle_init/1`.
  """
  @type client_behaviour_spec :: ClientHandler.t() | {ClientHandler.t(), opts :: any()}

  @type server_identifier :: pid() | atom()

  @doc """
  Starts the RTMP server.
  """
  @spec start_link(server_options :: t()) :: GenServer.on_start()
  def start_link(server_options) do
    gen_server_opts = if server_options[:name] == nil, do: [], else: [name: server_options[:name]]
    server_options_map = Enum.into(server_options, %{})
    server_options_map = Map.merge(@default_options, server_options_map)

    ssl_options_map =
      if is_nil(server_options[:ssl_options]) do
        %{ssl_options: Application.get_env(:membrane_rtmp_plugin, :ssl, [])}
      else
        %{ssl_options: server_options[:ssl_options]}
      end

    server_options_map = Map.merge(server_options_map, ssl_options_map)

    GenServer.start_link(__MODULE__, server_options_map, gen_server_opts)
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
      Task.start_link(Membrane.RTMPServer.Listener, :run, [
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
