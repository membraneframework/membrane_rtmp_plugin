defmodule Membrane.RTMPServer.Listener do
  @moduledoc false

  # Module responsible for maintaining the listening socket.

  use Task
  require Logger
  alias Membrane.RTMPServer.ClientHandler

  @spec run(
          options :: %{
            use_ssl?: boolean(),
            socket_module: :gen_tcp | :ssl,
            server: pid(),
            port: non_neg_integer()
          }
        ) :: no_return()
  def run(options) do
    options = Map.merge(options, %{socket_module: if(options.use_ssl?, do: :ssl, else: :gen_tcp)})

    listen_options =
      if options.use_ssl? do
        certfile = System.get_env("CERT_PATH")
        keyfile = System.get_env("CERT_KEY_PATH")

        [
          :binary,
          packet: :raw,
          active: false,
          certfile: certfile,
          keyfile: keyfile
        ]
      else
        [
          :binary,
          packet: :raw,
          active: false
        ]
      end

    {:ok, socket} = options.socket_module.listen(options.port, listen_options)
    send(options.server, {:port, :inet.port(socket)})

    accept_loop(socket, options)
  end

  defp accept_loop(socket, options) do
    {:ok, client} = :gen_tcp.accept(socket)

    {:ok, client_reference} =
      GenServer.start_link(ClientHandler,
        socket: client,
        use_ssl?: options.use_ssl?,
        server: options.server,
        handle_new_client: options.handle_new_client,
        client_timeout: options.client_timeout
      )

    case :gen_tcp.controlling_process(client, client_reference) do
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
