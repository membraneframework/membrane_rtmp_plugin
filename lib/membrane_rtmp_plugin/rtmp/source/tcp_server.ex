defmodule Membrane.RTMP.Source.TcpServer do
  @moduledoc """
  A simple tcp server, which executes given function for each new incoming connection.

  ## Example
  ```
  alias Membrane.RTMP.Source.TcpServer

  ip_addr = {127, 0, 0, 1}
  port = 9000

  server_options = %TcpServer{
  port: port,
  listen_options: [
    :binary,
    packet: :raw,
    active: false,
    ip: ip_addr
  ],
  socket_handler: fn socket ->
    {:ok, receive_task} =
      Task.start(fn ->
        {:ok, data} = :gen_tcp.recv(socket, 0)
        IO.inspect(data, label: "Received")
      end)

    {:ok, receive_task}
  end
  }

  TcpServer.start_link(server_options)

  Process.sleep(500)

  {:ok, socket} = :gen_tcp.connect(ip_addr, port, [], :infinity)

  :gen_tcp.send(socket, "Hello World")
  # Received: "Hello World"
  ```
  """
  use Task

  @enforce_keys [:port, :listen_options, :socket_handler]

  defstruct @enforce_keys

  @typedoc """
  Defines options for the TCP server.
  The `listen_options` are passed to the `:gen_tcp.listen/2` function.
  The `socket_handler` is a function that takes socket returned by `:gen_tcp.accept/1` and returns the pid of a process, which will be interacting with the socket. TcpServer will grant that process control over the socket via `:gen_tcp.controlling_process/2`.
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
