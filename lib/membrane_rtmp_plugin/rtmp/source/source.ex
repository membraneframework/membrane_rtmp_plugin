defmodule Membrane.RTMP.Source do
  @moduledoc """
  Membrane Element for receiving RTMP streams. Acts as a RTMP Server.
  This implementation is limited to only AAC and H264 streams.
  """
  use Membrane.Source

  require Membrane.Logger

  alias Membrane.{AVC, Buffer, Time, Logger}
  alias Membrane.RTMP.{Interceptor, Handshake}

  def_output_pad :audio,
    availability: :always,
    caps: Membrane.AAC.RemoteStream,
    mode: :pull

  def_output_pad :video,
    availability: :always,
    caps: Membrane.H264.RemoteStream,
    mode: :pull

  def_options port: [
                spec: non_neg_integer(),
                description: """
                Port on which the FFmpeg instance will be created
                """
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
       provider: nil,
       stale_frame: nil,
       interceptor: Interceptor.init(Handshake.init_server())
     })}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    target_pid = self()

    Logger.debug("Establishing connection on port: #{state.port}")

    spawn_link(fn ->
      {:ok, socket} =
        :gen_tcp.listen(state.port, [:binary, packet: :line, active: false, reuseaddr: true])

      {:ok, client} = :gen_tcp.accept(socket)

      Logger.debug("Established connection with client, socket: #{inspect(client)}")

      receive_loop(client, target_pid)
    end)

    # actions = [
    #   caps:
    #     {:video,
    #      %Membrane.H264.RemoteStream{
    #        decoder_configuration_record:
    #          <<1::8, 0::8, 0::8, 0::8, 0b111111::6, 0::2, 0b111::3, 0::13>>,
    #        stream_format: :avc1
    #      }},
    #   # caps: {:audio, %Membrane.AAC.RemoteStream{audio_specific_config: <<1::5, 0::4, 0::4, 0::1>>}},
    #   buffer: {:video, %Membrane.Buffer{payload: nil}}
    #   # buffer: {:audio, %Membrane.Buffer{payload: nil}}
    # ]

    {:ok, state}
  end

  defp receive_loop(socket, target) do
    {:ok, data} = :gen_tcp.recv(socket, 0)
    Logger.debug("Received data of size #{byte_size(data)}")
    send(target, {:tcp, data})
    receive_loop(socket, target)
  end

  @impl true
  def handle_demand(type, _size, _unit, _ctx, %{stale_frame: {type, buffer}} = state) do
    # There is stale frame, which indicates that that the source was blocked waiting for demand from one of the outputs
    # It now arrived, so we request next frame and output the one that blocked us
    send(state.provider, :get_frame)
    {{:ok, buffer: {type, buffer}}, %{state | stale_frame: nil}}
  end

  @impl true
  def handle_demand(_type, _size, _unit, _ctx, state) do
    {:ok, state}
  end

  @impl true
  def handle_playing_to_prepared(_ctx, state) do
    send(state.provider, :terminate)
    Process.unlink(state.provider)
    {:ok, %{state | provider: nil}}
  end

  @impl true
  def handle_other({:tcp, data}, _context, state) do
    Logger.debug(
      "Source received a packet of length: #{byte_size(data)}, handling with #{inspect(state.interceptor)}"
    )

    parsed_packet =
      data
      |> parse_packet_messages(state.interceptor)

    Logger.debug("Pared packet: #{inspect(parsed_packet)}")

    {:ok, state}
  end

  # The RTMP connection is based on TCP therefore we are operating on a continuous stream of bytes.
  # In such case packets received on TCP sockets may contain a partial RTMP packet or several full packets.
  #
  # `Interceptor` is already able to request more data if packet is incomplete but it is not aware
  # if its current buffer contains more than one message, therefore we need to call the `&Interceptor.handle_packet/2`
  # as long as we decide to receive more messages (before starting to relay media packets).
  #
  # Once we hit `:need_more_data` the function returns the list of parsed messages and the interceptor then is ready
  # to receive more data to continue with emitting new messages.
  @spec parse_packet_messages(packet :: binary(), interceptor :: struct(), [any()]) ::
          {[Message.t()], interceptor :: struct()}
  defp parse_packet_messages(packet, interceptor, messages \\ [])

  defp parse_packet_messages(<<>>, %{buffer: <<>>} = interceptor, messages) do
    {Enum.reverse(messages), interceptor}
  end

  defp parse_packet_messages(packet, interceptor, messages) do
    case Interceptor.handle_packet(packet, interceptor) do
      {_header, message, interceptor} ->
        parse_packet_messages(<<>>, interceptor, [message | messages])

      {:need_more_data, interceptor} ->
        {Enum.reverse(messages), interceptor}

      {:handshake_done, interceptor} ->
        parse_packet_messages(<<>>, interceptor, messages)

      {%Membrane.RTMP.Handshake.Step{} = step, interceptor} ->
        parse_packet_messages(<<>>, interceptor, [step | messages])
    end
  end
end
