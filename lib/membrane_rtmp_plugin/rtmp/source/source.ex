defmodule Membrane.RTMP.Source do
  @moduledoc """
  Membrane Element for receiving an RTMP stream. Acts as a RTMP Server.

  When initializing, the source sends `t:socket_control_needed_t/0` notification,
  upon which it should be granted the control over the `socket` via `:gen_tcp.controlling_process/2`.

  The Source allows for providing custom validator module, that verifies some of the RTMP messages.
  The module has to implement the `Membrane.RTMP.MessageValidator` behaviour.
  If the validation fails, a `t:stream_validation_failed_t/0` notification is sent.

  This implementation is limited to only AAC and H264 streams.
  """
  use Membrane.Source

  require Membrane.Logger

  alias Membrane.RTMP.{Handshake, MessageHandler, MessageParser}

  def_output_pad :output,
    availability: :always,
    caps: Membrane.RemoteStream,
    mode: :pull

  def_options socket: [
                spec: :gen_tcp.socket(),
                description: """
                Socket on which the source will be receiving the RTMP stream. The socket must be already connected to the RTMP client and be in non-active mode (`active` set to `false`).
                """
              ],
              validator: [
                spec: Membrane.RTMP.MessageValidator,
                description: """
                A Module implementing `Membrane.RTMP.MessageValidator` behaviour, used for validating the stream.
                """
              ]

  @typedoc """
  Notification sent when the RTMP Source element is initialized and it should be granted control over the socket using `:gen_tcp.controlling_process/2`.
  """
  @type socket_control_needed_t() :: {:socket_control_needed, :gen_tcp.socket(), pid()}

  @type validation_stage_t :: :publish | :release_stream | :set_data_frame

  @typedoc """
  Notification sent when the validator approves given validation stage..
  """
  @type stream_validation_success_t() ::
          {:stream_validation_success, validation_stage_t(), result :: any()}

  @typedoc """
  Notification sent when the validator denies incoming RTMP stream.
  """
  @type stream_validation_failed_t() ::
          {:stream_validation_failed, validation_stage_t(), reason :: any()}

  @typedoc """
  Notification sent when the socket has been closed but no media data has flown through it.

  This notification is only sent when the `:output` pad never reaches `:start_of_stream`.
  """
  @type unexpected_socket_closed_t() :: :unexpected_socket_closed

  @impl true
  def handle_init(%__MODULE__{} = opts) do
    {{:ok, [notify: {:socket_control_needed, opts.socket, self()}]},
     Map.from_struct(opts)
     |> Map.merge(%{
       actions: [],
       header_sent?: false,
       message_parser: MessageParser.init(Handshake.init_server()),
       receiver_pid: nil,
       socket_ready?: false,
       # how many times the Source tries to get control of the socket
       socket_retries: 3,
       # epoch required for performing a handshake with the pipeline
       epoch: 0
     })}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    target_pid = self()

    {:ok, receiver_process} =
      Task.start_link(fn ->
        receive_loop(state.socket, target_pid)
      end)

    send(self(), :start_receiving)

    actions = [
      caps: {:output, %Membrane.RemoteStream{content_format: Membrane.FLV, type: :bytestream}}
    ]

    {{:ok, actions}, %{state | receiver_pid: receiver_process}}
  end

  defp receive_loop(socket, target) do
    receive do
      {:tcp, _port, packet} ->
        send(target, {:tcp, socket, packet})

      {:tcp_closed, _port} ->
        send(target, {:tcp_closed, socket})

      :terminate ->
        exit(:normal)

      _message ->
        :noop
    end

    receive_loop(socket, target)
  end

  @impl true
  def handle_demand(_pad, _size, _unit, _ctx, state) when state.socket_ready? do
    :inet.setopts(state.socket, active: :once)
    {:ok, state}
  end

  @impl true
  def handle_demand(_pad, _size, _unit, _ctx, state) do
    {:ok, state}
  end

  @impl true
  def handle_playing_to_prepared(_ctx, state) do
    send(state.receiver_pid, :terminate)
    {:ok, %{state | receiver_pid: nil}}
  end

  @impl true
  def handle_other(:start_receiving, _ctx, %{socket_retries: 0} = state) do
    Membrane.Logger.warn("Failed to take control of the socket")
    {:ok, state}
  end

  def handle_other(:start_receiving, _ctx, %{socket_retries: retries} = state) do
    case :gen_tcp.controlling_process(state.socket, state.receiver_pid) do
      :ok ->
        :ok = :inet.setopts(state.socket, active: :once)
        {:ok, %{state | socket_ready?: true}}

      {:error, :not_owner} ->
        Process.send_after(self(), :start_receiving, 200)
        {:ok, %{state | socket_retries: retries - 1}}
    end
  end

  @impl true
  def handle_other({:tcp, socket, packet}, _ctx, state) do
    state = %{state | socket: socket}

    {messages, message_parser} =
      MessageHandler.parse_packet_messages(packet, state.message_parser)

    state = MessageHandler.handle_client_messages(messages, state)
    {actions, state} = get_actions(state)

    {{:ok, actions}, %{state | message_parser: message_parser}}
  end

  @impl true
  def handle_other({:tcp_closed, _socket}, ctx, state) do
    if ctx.pads.output.start_of_stream? do
      {{:ok, end_of_stream: :output}, state}
    else
      {{:ok, notify: :unexpected_socket_closed}, state}
    end
  end

  @impl true
  def handle_other(_message, _ctx, state) do
    {:ok, state}
  end

  defp get_actions(state) do
    case state do
      %{actions: [_action | _rest] = actions} ->
        {actions, %{state | actions: []}}

      _state ->
        {[], state}
    end
  end
end
