defmodule Membrane.RTMP.Server do
  @moduledoc """
  A simple RTMP server, which handles each new incoming connection.
  """

  use Task

  require Logger

  alias Membrane.RTMP.Server.ClientHandler
  @enforce_keys [:port, :behaviour]

  defstruct @enforce_keys

  @typedoc """
  Defines options for the RTMP server.
  """
  @type t :: %__MODULE__{
          port: :inet.port_number(),
          behaviour: Membrane.RTMP.Server.Behaviour.t()
        }

  @spec start_link(t()) :: {:ok, pid}
  def start_link(port: port, behaviour: behaviour, initial_state: initial_state) do
    Task.start_link(__MODULE__, :run, [port, behaviour, initial_state])
  end

  def run(port, behaviour, initial_state) do
    options = %{use_ssl?: false, port: port, behaviour: behaviour, initial_state: initial_state}
    {:ok, socket} = :gen_tcp.listen(options.port, [:binary, active: false])

    accept_loop(socket, options)
  end

  defp accept_loop(socket, options) do
    {:ok, client} = :gen_tcp.accept(socket)

    {:ok, client_handler} =
      GenServer.start_link(ClientHandler, socket: client, use_ssl?: options.use_ssl?, behaviour: options.behaviour, init_state: options.initial_state)

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
