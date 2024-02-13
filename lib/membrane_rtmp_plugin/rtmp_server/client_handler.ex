defmodule Membrane.RTMP.Server.ClientHandler do
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
