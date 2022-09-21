defmodule Membrane.RTMP.Source.TcpServer do
  @moduledoc """
  A simple tcp server, which handles each new incoming connection.

  The `socket_handler` function passed inside the options should take the socket returned by `:gen_tcp.accept/1`
  and return `{:ok, pid}`, where the `pid` describes a process, which will be interacting with the socket.
  `Membrane.RTMP.Source.TcpServer` will grant that process control over the socket via `:gen_tcp.controlling_process/2`.
  """

  use Task

  @enforce_keys [:port, :listen_options, :socket_handler]

  defstruct @enforce_keys

  @typedoc """
  Defines options for the TCP server.
  The `listen_options` are passed to the `:gen_tcp.listen/2` function.
  The `socket_handler` is a function that takes socket returned by `:gen_tcp.accept/1` and returns the pid of a process,
  which will be interacting with the socket. TcpServer will grant that process control over the socket via `:gen_tcp.controlling_process/2`.
  """
  @type t :: %__MODULE__{
          port: :inet.port_number(),
          listen_options: [:inet.inet_backend() | :gen_tcp.listen_option()],
          socket_handler: (:gen_tcp.socket() -> {:ok, pid} | {:error, reason :: any()})
        }

  @spec start_link(t()) :: {:ok, pid}
  def start_link(options) do
    Task.start_link(__MODULE__, :run, [Map.from_struct(options)])
  end

  @spec run(map()) :: nil
  def run(options) do
    {:ok, socket} = :gen_tcp.listen(options.port, options.listen_options)

    accept_loop(socket, options.socket_handler)
  end

  defp accept_loop(socket, socket_handler) do
    {:ok, client} = :gen_tcp.accept(socket)
    {:ok, handler_task} = Task.start(fn -> serve(client, socket_handler) end)

    :ok = :gen_tcp.controlling_process(client, handler_task)
    send(handler_task, :control_granted)

    accept_loop(socket, socket_handler)
  end

  defp serve(socket, socket_handler) do
    {:ok, pid} = socket_handler.(socket)

    receive do
      :control_granted ->
        :ok = :gen_tcp.controlling_process(socket, pid)
    end
  end
end
