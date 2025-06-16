defmodule Membrane.RTMPServer.Listener do
  @moduledoc false

  # Module responsible for maintaining the listening socket.

  use Task
  require Logger
  alias Membrane.RTMPServer.{ClientHandler, Config}

  @spec run(
          options :: %{
            use_ssl?: boolean(),
            socket_module: :gen_tcp | :ssl,
            server: pid(),
            port: non_neg_integer(),
            ssl_options: keyword()
          }
        ) :: no_return()
  def run(options) do
    options = Map.merge(options, %{socket_module: if(options.use_ssl?, do: :ssl, else: :gen_tcp)})

    listen_options =
      if options.use_ssl? do
        ssl_opts = Config.get_ssl_listen_options(Map.get(options, :ssl_options, []), true)

        Logger.debug("SSL options for listen: #{inspect(ssl_opts)}")

        # SSL listen requires at least certfile and keyfile
        unless ssl_opts[:certfile] && ssl_opts[:keyfile] do
          raise ArgumentError, """
          SSL is enabled but certificate files are not configured.
          Please configure SSL certificate files via:

          1. Application config:
             config :membrane_rtmp_plugin, :ssl,
               certfile: "/path/to/cert.pem",
               keyfile: "/path/to/key.pem"

          2. Environment variables:
             RTMP_SSL_CERTFILE="/path/to/cert.pem"
             RTMP_SSL_KEYFILE="/path/to/key.pem"

          3. Runtime options:
             ssl_options: [
               certfile: "/path/to/cert.pem",
               keyfile: "/path/to/key.pem"
             ]
          """
        end

        # Additional validation for certificate files
        if ssl_opts[:certfile] && !File.exists?(ssl_opts[:certfile]) do
          raise ArgumentError, "SSL certificate file does not exist: #{ssl_opts[:certfile]}"
        end

        if ssl_opts[:keyfile] && !File.exists?(ssl_opts[:keyfile]) do
          raise ArgumentError, "SSL key file does not exist: #{ssl_opts[:keyfile]}"
        end

        basic_opts = Config.get_listen_options()
        combined = basic_opts ++ ssl_opts
        Logger.debug("Combined listen options: #{inspect(combined)}")
        combined
      else
        Config.get_listen_options()
      end

    {:ok, socket} = options.socket_module.listen(options.port, listen_options)

    port =
      case options.socket_module do
        :gen_tcp ->
          {:ok, {_ip, port}} = :inet.sockname(socket)
          port

        :ssl ->
          {:ok, {_ip, port}} = :ssl.sockname(socket)
          port
      end

    send(options.server, {:port, port})

    accept_loop(socket, options)
  end

  defp accept_loop(socket, options) do
    client =
      case options.socket_module do
        :gen_tcp ->
          {:ok, client} = :gen_tcp.accept(socket)
          client

        :ssl ->
          {:ok, client} = :ssl.transport_accept(socket)
          Logger.debug("SSL transport accept successful, starting handshake...")

          ssl_handshake_opts =
            Config.get_ssl_handshake_options(Map.get(options, :ssl_options, []), false)

          ssl_handshake_opts =
            ssl_handshake_opts
            |> Keyword.put(:verify, :verify_none)
            |> Keyword.put(:fail_if_no_peer_cert, false)

          Logger.debug("SSL handshake options: #{inspect(ssl_handshake_opts)}")

          case :ssl.handshake(client, ssl_handshake_opts, 10_000) do
            {:ok, ssl_socket} ->
              Logger.info("SSL handshake successful")
              ssl_socket

            :ok ->
              Logger.info("SSL handshake successful (ok)")
              client

            {:error, reason} ->
              Logger.error("SSL handshake failed: #{inspect(reason)}")
              :ssl.close(client)
              accept_loop(socket, options)
          end
      end

    {:ok, client_reference} =
      GenServer.start_link(ClientHandler,
        socket: client,
        use_ssl?: options.use_ssl?,
        server: options.server,
        handle_new_client: options.handle_new_client,
        client_timeout: options.client_timeout
      )

    case options.socket_module.controlling_process(client, client_reference) do
      :ok ->
        send(client_reference, :control_granted)

      {:error, reason} ->
        Logger.error(
          "Couldn't pass control to process: #{inspect(client_reference)} due to: #{inspect(reason)}"
        )
    end

    accept_loop(socket, options)
  end
end
