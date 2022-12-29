defmodule Membrane.RTMP.Source.TcpServerTest do
  use ExUnit.Case, async: true

  alias Membrane.RTMP.Source.TcpServer

  @port 9000
  @local_ip "127.0.0.1" |> String.to_charlist() |> :inet.parse_address() |> elem(1)
  @sample_data "Hello World"

  test "TcpServer transfers the control to the process " do
    testing_process = self()

    server_options = %TcpServer{
      port: @port,
      listen_options: [
        :binary,
        packet: :raw,
        active: false,
        reuseaddr: true,
        ip: @local_ip
      ],
      socket_handler: fn socket ->
        {:ok, receive_task} =
          Task.start(fn ->
            testing_process |> Process.link()
            :inet.setopts(socket, active: true)

            data = @sample_data
            assert_receive({:tcp, ^socket, ^data}, 1000)
          end)

        {:ok, receive_task}
      end
    }

    {:ok, _pid} = TcpServer.start_link(server_options)

    Process.sleep(500)

    {:ok, socket} =
      :gen_tcp.connect(
        @local_ip,
        @port,
        [],
        :infinity
      )

    :gen_tcp.send(socket, @sample_data)
    assert_receive({:tcp_closed, ^socket}, 1000)
  end
end
