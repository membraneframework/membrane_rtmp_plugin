defmodule Membrane.RTMP.Source.SslServerTest do
  use ExUnit.Case, async: true

  alias Membrane.RTMP.Source.SslServer

  @port 9000
  @local_ip "127.0.0.1" |> String.to_charlist() |> :inet.parse_address() |> elem(1)
  @sample_data "Hello World"

  @tag :rtmps
  test "SslServer transfers the control to the process " do
    testing_process = self()

    certfile = System.get_env("CERT_PATH")
    keyfile = System.get_env("CERT_KEY_PATH")

    server_options = %SslServer{
      parent: self(),
      port: @port,
      listen_options: [
        :binary,
        packet: :raw,
        active: false,
        reuseaddr: true,
        ip: @local_ip,
        certfile: certfile,
        keyfile: keyfile
      ],
      socket_handler: fn socket ->
        {:ok, receive_task} =
          Task.start(fn ->
            testing_process |> Process.link()
            :ssl.setopts(socket, active: true)

            data = @sample_data
            assert_receive {:ssl, ^socket, ^data}, 1000
          end)

        {:ok, receive_task}
      end
    }

    start_supervised!({SslServer, [server_options]})

    assert_receive {:ssl_server_started, _socket}

    {:ok, socket} =
      :ssl.connect(
        'localhost',
        @port,
        [
          cacertfile: certfile,
          verify_fun:
            {fn
               _cert, _result, state ->
                 {:valid, state}
             end, []},
          verify: :verify_none
        ],
        :infinity
      )

    :ok = :ssl.send(socket, @sample_data)
    assert_receive({:ssl_closed, ^socket}, 1_500)
  end
end
