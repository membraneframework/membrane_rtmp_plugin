defmodule Membrane.RTMPServerTest do
  use ExUnit.Case, async: true

  @handshake_size 1536
  @c1_time_and_zero_size 8
  @c1_random_size @handshake_size - @c1_time_and_zero_size
  @s0_s1_s2_size 1 + 2 * @handshake_size
  @recv_timeout 2_000
  @open_connection_probe_timeout 200
  @rtmp_version 0x03
  @invalid_rtmp_version 0x00

  setup do
    {:ok, server} =
      Membrane.RTMPServer.start_link(
        port: 0,
        handle_new_client: fn _client_ref, _app, _stream_key ->
          Membrane.RTMP.Source.ClientHandlerImpl
        end
      )

    port = Membrane.RTMPServer.get_port(server)
    server_monitor = Process.monitor(server)

    %{server: server, port: port, server_monitor: server_monitor}
  end

  test "malformed handshake closes only the offending connection", ctx do
    socket = connect(ctx.port)
    :ok = :gen_tcp.send(socket, malformed_c0_c1())

    assert {:error, :closed} = :gen_tcp.recv(socket, 0, @recv_timeout)
    refute_received {:DOWN, _ref, :process, _pid, _reason}
    assert Process.alive?(ctx.server)
  end

  test "malformed handshake doesn't disconnect other clients", ctx do
    healthy = connect(ctx.port)
    :ok = :gen_tcp.send(healthy, valid_c0_c1())

    assert {:ok, <<@rtmp_version, _rest::binary>>} =
             :gen_tcp.recv(healthy, @s0_s1_s2_size, @recv_timeout)

    malicious = connect(ctx.port)
    :ok = :gen_tcp.send(malicious, malformed_c0_c1())
    assert {:error, :closed} = :gen_tcp.recv(malicious, 0, @recv_timeout)

    assert {:error, :timeout} = :gen_tcp.recv(healthy, 0, @open_connection_probe_timeout)
    assert {:ok, _peer} = :inet.peername(healthy)

    fresh = connect(ctx.port)
    :ok = :gen_tcp.send(fresh, valid_c0_c1())

    assert {:ok, <<@rtmp_version, _rest::binary>>} =
             :gen_tcp.recv(fresh, @s0_s1_s2_size, @recv_timeout)

    refute_received {:DOWN, _ref, :process, _pid, _reason}
    assert Process.alive?(ctx.server)
  end

  defp connect(port) do
    {:ok, socket} = :gen_tcp.connect(~c"localhost", port, [:binary, active: false])
    socket
  end

  defp valid_c0_c1() do
    <<@rtmp_version, 0::size(@c1_time_and_zero_size * 8),
      :crypto.strong_rand_bytes(@c1_random_size)::binary>>
  end

  defp malformed_c0_c1(), do: <<@invalid_rtmp_version, 0::size(@handshake_size * 8)>>
end
