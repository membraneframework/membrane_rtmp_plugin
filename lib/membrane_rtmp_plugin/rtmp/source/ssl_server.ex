defmodule Membrane.RTMP.Source.SslServer do
  @moduledoc """
  A simple ssl server, which handles each new incoming connection.

  The `socket_handler` function passed inside the options should take the socket returned by `:ssl.handshake/1`
  and return `{:ok, pid}`, where the `pid` describes a process, which will be interacting with the socket.
  `#{inspect(__MODULE__)}` will grant that process control over the socket via `:ssl.controlling_process/2`.
  """

  use Task

  @enforce_keys [
    :port,
    :listen_options,
    :socket_handler
  ]

  defstruct @enforce_keys ++ [:parent]

  @typedoc """
  Defines options for the SSL server.
  The `listen_options` are passed to the `:ssl.listen/2` function.
  The `socket_handler` is a function that takes socket returned by `:gen_tcp.accept/1` and returns the pid of a process,
  which will be interacting with the socket. SslServer will grant that process control over the socket via `:ssl.controlling_process/2`.
  """
  @type t :: %__MODULE__{
          port: :inet.port_number(),
          listen_options: [:inet.inet_backend() | :ssl.tls_server_option()],
          socket_handler: (:ssl.sslsocket() -> {:ok, pid} | {:error, reason :: any()}),
          parent: pid()
        }

  @spec start_link(t()) :: {:ok, pid}
  def start_link(options) do
    Task.start_link(__MODULE__, :run, [options])
  end

  @spec run(t()) :: nil
  def run(options) do
    {:ok, socket} = :ssl.listen(options.port, options.listen_options)
    if options.parent, do: send(options.parent, {:ssl_server_started, socket})

    accept_loop(socket, options.socket_handler)
  end

  defp accept_loop(socket, socket_handler) do
    {:ok, ssl_socket} = :ssl.transport_accept(socket)
    {:ok, ssl_socket} = :ssl.handshake(ssl_socket)
    {:ok, pid} = socket_handler.(ssl_socket)
    :ok = :ssl.controlling_process(ssl_socket, pid)
    # send(pid, :granted_control)

    accept_loop(socket, socket_handler)
  end
end
