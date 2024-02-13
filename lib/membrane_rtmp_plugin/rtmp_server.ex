defmodule RTMP do
  defmodule ClientHandler do
    use GenServer

    alias Membrane.RTMP.{Handshake, MessageHandler, MessageParser}

    def init(opts) do
      opts = Map.new(opts)

      {:ok,
       %{
         socket: opts.socket,
         socket_module: if(opts.use_ssl?, do: :ssl, else: :gen_tcp),
         header_sent?: false,
         message_parser: MessageParser.init(Handshake.init_server()),
         actions: [],
         validator: %Membrane.RTMP.MessageValidator.Default{},
         receiver_pid: nil,
         socket_ready?: true,
         # how many times the Source tries to get control of the socket
         socket_retries: 3,
         # epoch required for performing a handshake with the pipeline
         epoch: 0
       }}
    end

    def handle_info({:tcp, socket, data}, %{socket_module: :gen_tcp} = state)
        when state.socket == socket do
      {messages, message_parser} =
        MessageHandler.parse_packet_messages(data, state.message_parser)

      state = MessageHandler.handle_client_messages(messages, state)
      {:noreply, %{state | actions: [], message_parser: message_parser}}
    end

    def handle_info({:ssl, socket, data}, %{socket_module: :ssl} = state)
        when state.socket == socket do
      {messages, message_parser} =
        MessageHandler.parse_packet_messages(data, state.message_parser)

      state = MessageHandler.handle_client_messages(messages, state)
      {:noreply, %{state | actions: [], message_parser: message_parser}}
    end

    def handle_info(:control_granted, state) do
      case state.socket_module do
        :gen_tcp -> :inet.setopts(state.socket, active: :once)
        :ssl -> :ssl.setopts(state.socket, active: :once)
      end

      {:noreply, state}
    end

    def handle_info(_msg, state) do
      {:noreply, state}
    end
  end

  @moduledoc """
  A simple RTMP server, which handles each new incoming connection.
  """

  use Task

  require Logger

  @enforce_keys [:port]

  defstruct @enforce_keys

  @typedoc """
  Defines options for the TCP server.
  The `socket_handler` is a function that takes socket returned by `:gen_tcp.accept/1` and returns the pid of a process,
  which will be interacting with the socket.
  """
  @type t :: %__MODULE__{
          port: :inet.port_number()
        }

  @spec start_link(t()) :: {:ok, pid}
  def start_link(options) do
    Task.start_link(__MODULE__, :run, options)
  end

  @spec run(t()) :: no_return()
  def run(options) do
    options = Map.merge(%{use_ssl?: false}, Map.new(options))
    {:ok, socket} = :gen_tcp.listen(options.port, [:binary, active: false])

    accept_loop(socket, options)
  end

  defp accept_loop(socket, options) do
    {:ok, client} = :gen_tcp.accept(socket)

    {:ok, client_handler} =
      GenServer.start_link(ClientHandler, socket: client, use_ssl?: options.use_ssl?)

    case :gen_tcp.controlling_process(client, client_handler) do
      :ok ->
        send(client_handler, :control_granted)

      {:error, reason} ->
        Logger.error(
          "Couldn't pass control to process: #{inspect(client_handler)} due to: #{inspect(reason)}"
        )
    end

    accept_loop(socket, options)
  end
end
