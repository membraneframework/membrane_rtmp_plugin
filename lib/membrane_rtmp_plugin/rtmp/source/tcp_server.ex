defmodule Membrane.RTMP.Source.TcpServer do
  @moduledoc """
  A simple tcp server, which handles each new incoming connection.

  The `socket_handler` function passed inside the options should take the socket returned by `:gen_tcp.accept/1`
  and return `{:ok, pid}`, where the `pid` describes a process, which will be interacting with the socket. The process
  will be temporarily linked with a `#{inspect(__MODULE__)}` worker process until it successfully grants it the control
  over the socket using `:gen_tcp.controlling_process/2`.
  """

  use Task

  @enforce_keys [:port, :listen_options, :socket_handler]

  defstruct @enforce_keys ++ [:parent]

  @typedoc """
  Defines options for the TCP server.
  The `listen_options` are passed to the `:gen_tcp.listen/2` function.
  The `socket_handler` is a function that takes socket returned by `:gen_tcp.accept/1` and returns the pid of a process,
  which will be interacting with the socket.
  """
  @type t :: %__MODULE__{
          port: :inet.port_number(),
          listen_options: [:inet.inet_backend() | :gen_tcp.listen_option()],
          socket_handler: (:gen_tcp.socket() -> {:ok, pid} | {:error, reason :: any()}),
          parent: pid()
        }

  @spec start_link(t()) :: {:ok, pid}
  def start_link(options) do
    Task.start_link(__MODULE__, :run, [options])
  end

  @spec run(t()) :: no_return()
  def run(options) do
    {:ok, socket} = :gen_tcp.listen(options.port, options.listen_options)
    if options.parent, do: send(options.parent, {:tcp_server_started, socket})

    accept_loop(socket, options.socket_handler)
  end

  defp accept_loop(socket, socket_handler) do
    {:ok, client} = :gen_tcp.accept(socket)
    {:ok, handler_task} = Task.start(fn -> serve(client, socket_handler) end)

    case :gen_tcp.controlling_process(client, handler_task) do
      :ok -> send(handler_task, :control_granted)
      {:error, _reason} -> send(handler_task, :control_denied)
    end

    accept_loop(socket, socket_handler)
  end

  defp serve(socket, socket_handler) do
    {:ok, pid} = socket_handler.(socket)

    Process.link(pid)

    receive do
      :control_granted ->
        :gen_tcp.controlling_process(socket, pid)

      :control_denied ->
        {:error, :control_denied}
    after
      5000 -> {:error, :timeout}
    end
    |> case do
      :ok ->
        :ok

      {:error, reason} ->
        raise "Failed to grant control over the client socket due to #{inspect(reason)}"
    end
  end
end
