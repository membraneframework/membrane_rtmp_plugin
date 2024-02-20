defmodule Membrane.RTMP.Server.Listener do
  use Task
  alias Membrane.RTMP.Server.ClientHandler

  def run(port, behaviour, server, use_ssl?, listen_options) do
    options = %{
      use_ssl?: use_ssl?,
      behaviour: behaviour,
      server: server,
      socket_module: if(use_ssl?, do: :ssl, else: :gen_tcp)
    }

    {:ok, socket} = options.socket_module.listen(port, listen_options)
    send(server, {:port, :inet.port(socket)})

    accept_loop(socket, options)
  end

  defp accept_loop(socket, options) do
    {:ok, client} = :gen_tcp.accept(socket)

    {:ok, client_handler} =
      GenServer.start_link(ClientHandler,
        socket: client,
        use_ssl?: options.use_ssl?,
        behaviour: options.behaviour,
        server: options.server
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
