defmodule Membrane.RTMP.Source.TcpServer.Test do
  use ExUnit.Case

  alias Membrane.RTMP.Source.TcpServer

  @port 9000
  @local_ip "127.0.0.1"
  @sample_data "Hello World"

  test "TcpServer transfers the control to the process " do
    server_options = [
      port: @port,
      local_ip: @local_ip,
      tcp_options: [
        :binary,
        packet: :raw,
        active: false,
        reuseaddr: true,
        ip: @local_ip |> String.to_charlist() |> :inet.parse_address() |> elem(1)
      ],
      serve_fn: fn socket ->
        {:ok, receive_task} =
          Task.start(fn ->
            Process.whereis(__MODULE__) |> Process.link()
            :inet.setopts(socket, active: true)

            data = @sample_data
            assert_receive({:tcp, ^socket, ^data}, 1000)
          end)

        {:ok, receive_task}
      end
    ]

    Process.register(self(), __MODULE__)
    TcpServer.start_link(server_options)

    Process.sleep(500)

    {:ok, socket} =
      :gen_tcp.connect(
        @local_ip |> String.to_charlist() |> :inet.parse_address() |> elem(1),
        @port,
        [],
        :infinity
      )

    data = @sample_data

    :gen_tcp.send(socket, data)
    assert_receive({:tcp_closed, ^socket}, 1000)
  end
end
