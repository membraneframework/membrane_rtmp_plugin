defmodule RTMP do
  defmodule ClientHandler do
    use GenServer

    require Logger
    alias Membrane.RTMP.{Handshake, MessageHandler, MessageParser}

    def init(opts) do
      opts = Map.new(opts)

      {:ok,
       %{
         socket: opts.socket,
         use_ssl?: opts.use_ssl?,
         message_parser_state: Handshake.init_server() |> MessageParser.init(),
         message_handler_state: MessageHandler.init(opts)
       }}
    end

    def handle_info({:tcp, socket, data}, %{use_ssl?: false} = state)
        when state.socket == socket do
      handle_data(data, state)
    end

    def handle_info({:ssl, socket, data}, %{use_ssl?: true} = state)
        when state.socket == socket do
      handle_data(data, state)
    end

    def handle_info(:control_granted, state) do
      case state.use_ssl? do
        false -> :inet.setopts(state.socket, active: :once)
        true -> :ssl.setopts(state.socket, active: :once)
      end

      {:noreply, state}
    end

    def handle_info(msg, state) do
      Logger.warning("Unknown message received: #{inspect(msg)}")
      {:noreply, state}
    end

    defp handle_data(data, state) do
      {messages, message_parser_state} =
        MessageParser.parse_packet_messages(data, state.message_parser_state)

      {message_handler_state, actions} =
        MessageHandler.handle_client_messages(messages, state.message_handler_state)

      state = handle_actions(actions, state)

      {:noreply,
       %{
         state
         | message_parser_state: message_parser_state,
           message_handler_state: message_handler_state
       }}
    end

    defp handle_actions([], state) do
      state
    end

    defp handle_actions([action | rest], state) do
      # call callbacks
      case action do
        :end_of_stream ->
          nil

        {:set_chunk_size, _size} ->
          nil

        {:output, payload} ->
          nil

        {:connected, app} ->
          nil

        {:published, stream_key} ->
          nil

        {:stream_validation_success, stage, msg} ->
          nil

        {:stream_validation_error, stage, reason} ->
          nil
      end

      handle_actions(rest, state)
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
