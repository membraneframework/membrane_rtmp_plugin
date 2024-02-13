defmodule Membrane.RTMP.Server do
  @moduledoc """
  A simple RTMP server, which handles each new incoming connection.
  """

  use Task

  require Logger

  alias Membrane.RTMP.Server.ClientHandler
  @enforce_keys [:port]

  defstruct @enforce_keys

  @typedoc """
  Defines options for the TCP server.
  The `socket_handler` is a function that takes socket returned by `:gen_tcp.accept/1` and returns the pid of a process,
  which will be interacting with the socket.
  """
  @type t :: %__MODULE__{
          port: :inet.port_number()
        }

  @spec start_link(t()) :: {:ok, pid}
  def start_link(options) do
    Task.start_link(__MODULE__, :run, options)
  end

  @spec run(t()) :: no_return()
  def run(options) do
    options = Map.merge(%{use_ssl?: false}, Map.new(options))
    {:ok, socket} = :gen_tcp.listen(options.port, [:binary, active: false])

    accept_loop(socket, options)
  end

  defp accept_loop(socket, options) do
    {:ok, client} = :gen_tcp.accept(socket)

    {:ok, client_handler} =
      GenServer.start_link(ClientHandler, socket: client, use_ssl?: options.use_ssl?)

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
