defmodule Membrane.RTMPServer.Listener do
  @moduledoc false

  # Module responsible for maintaining the listening socket.

  use Task
  require Logger
  alias Membrane.RTMPServer.ClientHandler

  @listen_opts [
    :binary,
    packet: :raw,
    active: false,
    reuseaddr: true
  ]

  @ssl_handshake_opts [
    :certfile,
    :keyfile,
    :cacertfile,
    :password,
    :versions
  ]

  @ssl_listen_opts [
    :verify,
    :fail_if_no_peer_cert,
    :versions,
    :ciphers,
    :honor_cipher_order,
    :secure_renegotiate,
    :reuse_sessions,
    :cacertfile,
    :depth,
    :log_level
  ]

  @spec run(
          options :: %{
            use_ssl?: boolean(),
            socket_module: :gen_tcp | :ssl,
            server: pid(),
            client_supervisor: pid(),
            port: non_neg_integer(),
            ssl_options: keyword()
          }
        ) :: no_return()
  def run(options) do
    options = Map.merge(options, %{socket_module: if(options.use_ssl?, do: :ssl, else: :gen_tcp)})

    listen_options =
      if options.use_ssl? do
        ssl_opts =
          options
          |> Map.get(:ssl_options, [])
          |> Keyword.take(@ssl_listen_opts)

        Logger.debug("SSL options for listen: #{inspect(ssl_opts)}")

        combined = @listen_opts ++ ssl_opts
        Logger.debug("Combined listen options: #{inspect(combined)}")
        combined
      else
        @listen_opts
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
            options
            |> Map.get(:ssl_options, [])
            |> Keyword.take(@ssl_handshake_opts)

          ssl_handshake_opts =
            ssl_handshake_opts
            |> Keyword.put(:verify, :verify_none)
            |> Keyword.put(:fail_if_no_peer_cert, false)

          Logger.debug("SSL handshake options: #{inspect(ssl_handshake_opts)}")

          case :ssl.handshake(client, ssl_handshake_opts, 10_000) do
            {:ok, ssl_socket} ->
              Logger.info("SSL handshake successful")
              ssl_socket

            {:error, reason} ->
              Logger.error("SSL handshake failed: #{inspect(reason)}")
              :ssl.close(client)
              accept_loop(socket, options)
          end
      end

    client_handler_opts = [
      socket: client,
      use_ssl?: options.use_ssl?,
      server: options.server,
      handle_new_client: options.handle_new_client,
      client_timeout: options.client_timeout
    ]

    options.client_supervisor
    |> DynamicSupervisor.start_child({ClientHandler, client_handler_opts})
    |> handle_client_handler_start(client, options)

    accept_loop(socket, options)
  end

  defp handle_client_handler_start({:ok, client_reference}, client, options) do
    client
    |> options.socket_module.controlling_process(client_reference)
    |> handle_control_transfer(client, client_reference, options)
  end

  defp handle_client_handler_start({:error, reason}, client, options) do
    Logger.error("Couldn't start client handler due to: #{inspect(reason)}")
    options.socket_module.close(client)
  end

  defp handle_control_transfer(:ok, _client, client_reference, _options) do
    send(client_reference, :control_granted)
  end

  defp handle_control_transfer({:error, reason}, client, client_reference, options) do
    Logger.error(
      "Couldn't pass control to process: #{inspect(client_reference)} due to: #{inspect(reason)}"
    )

    DynamicSupervisor.terminate_child(options.client_supervisor, client_reference)
    options.socket_module.close(client)
  end
end
