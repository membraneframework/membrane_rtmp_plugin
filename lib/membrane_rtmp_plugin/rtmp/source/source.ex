defmodule Membrane.RTMP.Source do
  @moduledoc """
  Membrane Element for receiving RTMP streams. Acts as a RTMP Server.
  This implementation assumes that audio and video is .
  """
  use Membrane.Source

  require Membrane.Logger

  alias Membrane.{Logger, Time}
  alias Membrane.RTMP.{Handshake, Interceptor, MessageHandler}

  def_output_pad :output,
    availability: :always,
    caps: Membrane.RemoteStream,
    mode: :pull

  def_options port: [
                spec: non_neg_integer(),
                description: """
                Port on which the server will be listen
                """
              ],
              local_ip: [
                spec: binary(),
                default: "127.0.0.1",
                description:
                  "IP address on which the server will listen. This is useful if you have more than one network interface"
              ],
              timeout: [
                spec: Time.t() | :infinity,
                default: :infinity,
                description: """
                Time the server will wait for a connection from the client

                Duration given must be a multiply of one second or atom `:infinity`.
                """
              ]

  @impl true
  def handle_init(%__MODULE__{} = opts) do
    {:ok,
     Map.from_struct(opts)
     |> Map.merge(%{
       stale_frame: nil,
       buffers: [],
       header_sent?: false,
       interceptor: Interceptor.init(Handshake.init_server()),
       client_pid: nil,
       client_socket: nil,
       client_connected?: false,
       # epoch required for performing a handshake with the pipeline
       epoch: 0
     })}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    target_pid = self()

    pid =
      spawn_link(fn ->
        {:ok, socket} =
          :gen_tcp.listen(state.port, [
            :binary,
            packet: :raw,
            active: :once,
            reuseaddr: true,
            ip:
              state.local_ip
              |> String.split(".")
              |> Enum.map(&String.to_integer/1)
              |> List.to_tuple()
          ])

        Logger.debug("established tcp connection")

        {:ok, client} = :gen_tcp.accept(socket)

        receive_loop(client, target_pid)
      end)

    actions = [
      caps: {:output, %Membrane.RemoteStream{content_format: Membrane.FLV, type: :bytestream}}
    ]

    {{:ok, actions}, %{state | client_pid: pid}}
  end

  defp receive_loop(socket, target) do
    receive do
      :need_more_data ->
        :inet.setopts(socket, active: :once)

      {:tcp, _port, packet} ->
        send(target, {:tcp, socket, packet})

      {:tcp_closed, _port} ->
        send(target, {:tcp_closed, socket})

      :terminate ->
        exit(:normal)

      message ->
        Logger.debug("Receiver got unknown message: #{inspect(message)}")
        :noop
    end

    receive_loop(socket, target)
  end

  @impl true
  def handle_demand(_pad, _size, _unit, _ctx, state) do
    send(state.client_pid, :need_more_data)
    {:ok, state}
  end

  @impl true
  def handle_playing_to_prepared(_ctx, state) do
    send(state.client_pid, :terminate)
    Process.unlink(state.client_pid)
    {:ok, %{state | client_pid: nil}}
  end

  @impl true
  def handle_other({:tcp, client_socket, packet}, _ctx, state) do
    state = %{state | client_socket: client_socket}

    {messages, interceptor} = MessageHandler.parse_packet_messages(packet, state.interceptor)

    state = MessageHandler.handle_client_messages(messages, state)
    {actions, state} = get_actions(state)

    {{:ok, actions}, %{state | interceptor: interceptor}}
  end

  @impl true
  def handle_other({:tcp_closed, _port}, _ctx, state) do
    {{:ok, end_of_stream: :output}, state}
  end

  @impl true
  def handle_other(message, _ctx, state) do
    Logger.debug("Source received unknown message: #{inspect(message)}")
    {:ok, state}
  end

  defp get_actions(state) do
    case state do
      %{buffers: [_buf | _rest] = buffers} ->
        {[buffer: {:output, Enum.reverse(buffers)}], %{state | buffers: []}}

      _state ->
        {[], state}
    end
  end
end
