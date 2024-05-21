defmodule Membrane.RTMP.Server.Listener do
  @moduledoc false

  # Module responsible for maintaining the listening socket.

  use Task
  require Logger
  alias Membrane.RTMP.Server.ClientHandler

  @spec run(
          options :: %{
            use_ssl?: boolean,
            socket_module: :gen_tcp | :ssl,
            server: pid(),
            port: non_neg_integer()
          }
        ) :: no_return()
  def run(options) do
    options = Map.merge(options, %{socket_module: if(options.use_ssl?, do: :ssl, else: :gen_tcp)})

    {:ok, socket} = options.socket_module.listen(options.port, options.listen_options)
    send(options.server, {:port, :inet.port(socket)})

    accept_loop(socket, options)
  end

  defp accept_loop(socket, options) do
    {:ok, client} = :gen_tcp.accept(socket)

    {:ok, client_handler} =
      GenServer.start_link(ClientHandler,
        socket: client,
        use_ssl?: options.use_ssl?,
        behaviour: options.behaviour,
        server: options.server,
        behaviour_options: options.behaviour_options
      )

    case :gen_tcp.controlling_process(client, client_handler) do
      :ok ->
        send(client_handler, :control_granted)

      {:error, reason} ->
        Logger.error(
          "Couldn't pass control to process: #{inspect(client_handler)} due to: #{inspect(reason)}"
        )
    end

    accept_loop(socket, options)
  end
end
