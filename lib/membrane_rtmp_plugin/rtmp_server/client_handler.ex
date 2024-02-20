defmodule Membrane.RTMP.Server.ClientHandler do
  use GenServer

  require Logger
  alias Membrane.RTMP.{Handshake, MessageHandler, MessageParser}
  alias Membrane.RTMP.Server.Behaviour

  def init(opts) do
    opts = Map.new(opts)

    {:ok,
     %{
       socket: opts.socket,
       use_ssl?: opts.use_ssl?,
       message_parser_state: Handshake.init_server() |> MessageParser.init(),
       message_handler_state: MessageHandler.init(opts),
       behaviour: opts.behaviour,
       behaviour_state: opts.behaviour.handle_init(),
       app: nil,
       stream_key: nil,
       server: opts.server
     }}
  end

  def handle_info({:tcp, socket, data}, %{use_ssl?: false} = state) when state.socket == socket do
    handle_data(data, state)
  end

  def handle_info({:tcp_closed, socket}, %{use_ssl?: false} = state)
      when state.socket == socket do
    events = [:end_of_stream]
    state = handle_events(events, state)

    {:noreply, state}
  end

  def handle_info({:ssl, socket, data}, %{use_ssl?: true} = state) when state.socket == socket do
    handle_data(data, state)
  end

  def handle_info({:ssl_closed, socket}, %{use_ssl?: true} = state) when state.socket == socket do
    events = [:end_of_stream]
    state = handle_events(events, state)

    {:noreply, state}
  end

  def handle_info(:control_granted, state) do
    case state.use_ssl? do
      false -> :inet.setopts(state.socket, active: :once)
      true -> :ssl.setopts(state.socket, active: :once)
    end

    {:noreply, state}
  end

  def handle_info(other_msg, state) do
    behaviour_state = state.behaviour.handle_info(other_msg, state.behaviour_state)

    {:noreply, %{state | behaviour_state: behaviour_state}}
  end

  def handle_info(msg, state) do
    Logger.warning("Unknown message received: #{inspect(msg)}")
    {:noreply, state}
  end

  defp handle_data(data, state) do
    {messages, message_parser_state} =
      MessageParser.parse_packet_messages(data, state.message_parser_state)

    {message_handler_state, events} =
      MessageHandler.handle_client_messages(messages, state.message_handler_state)

    state = handle_events(events, state)

    {:noreply,
     %{
       state
       | message_parser_state: message_parser_state,
         message_handler_state: message_handler_state
     }}
  end

  defp handle_events([], state) do
    state
  end

  defp handle_events([event | rest], state) do
    # call callbacks
    state =
      case event do
        :end_of_stream ->
          new_behaviour_state = state.behaviour.handle_end_of_stream(state.behaviour_state)
          %{state | behaviour_state: new_behaviour_state}

        {:set_chunk_size_required, chunk_size} ->
          new_message_parser_state = %{state.message_parser_state | chunk_size: chunk_size}
          %{state | message_parser_state: new_message_parser_state}

        {:data_available, payload} ->
          new_behaviour_state =
            state.behaviour.handle_data_available(payload, state.behaviour_state)

          %{state | behaviour_state: new_behaviour_state}

        {:connected, connected_msg} ->
          new_behaviour_state =
            state.behaviour.handle_connected(connected_msg, state.behaviour_state)

          %{state | behaviour_state: new_behaviour_state, app: connected_msg.app}

        {:published, publish_msg} ->
          send(state.server, {:register_client, state.app, publish_msg.stream_key, self()})

          new_behaviour_state =
            state.behaviour.handle_stream_published(publish_msg, state.behaviour_state)

          %{state | behaviour_state: new_behaviour_state, stream_key: publish_msg.stream_key}
      end

    handle_events(rest, state)
  end
end
