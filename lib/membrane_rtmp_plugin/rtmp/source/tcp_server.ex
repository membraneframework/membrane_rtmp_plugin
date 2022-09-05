defmodule Membrane.RTMP.Source.TcpServer do
  use Task

  def start_link(options) do
    Task.start_link(__MODULE__, :run, [Enum.into(options, %{})])
  end

  def run(options) do
    {:ok, socket} = :gen_tcp.listen(options.port, options.tcp_options)

    accept_loop(socket, options.serve_fn)
  end

  defp accept_loop(socket, serve_fn) do
    {:ok, client} = :gen_tcp.accept(socket)
    {:ok, pid} = Task.start(fn -> serve(client, serve_fn) end)
    :ok = :gen_tcp.controlling_process(client, pid)

    accept_loop(socket, serve_fn)
  end

  defp serve(socket, serve_fn) do
    {:ok, pid} = serve_fn.(socket)
    :ok = :gen_tcp.controlling_process(socket, pid)
  end
end
