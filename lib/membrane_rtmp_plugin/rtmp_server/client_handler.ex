defmodule Membrane.RTMP.Server.ClientHandler do
  @moduledoc false

  # Module responsible for maintaining the lifecycle of the
  # client connection.

  use GenServer

  require Logger
  alias Membrane.RTMP.{Handshake, MessageHandler, MessageParser}

  @doc """
  Makes the client handler ask client for the desired number of buffers
  """
  @spec demand_data(pid(), non_neg_integer()) :: :ok
  def demand_data(client_reference, how_many_buffers_demanded) do
    send(client_reference, {:demand_data, how_many_buffers_demanded})
    :ok
  end

  @impl true
  def init(opts) do
    opts = Map.new(opts)
    message_parser_state = Handshake.init_server() |> MessageParser.init()
    message_handler_state = MessageHandler.init(%{socket: opts.socket, use_ssl?: opts.use_ssl?})

    %handler_module{} = opts.handler

    {:ok,
     %{
       socket: opts.socket,
       use_ssl?: opts.use_ssl?,
       message_parser_state: message_parser_state,
       message_handler_state: message_handler_state,
       handler: handler_module,
       handler_state: handler_module.handle_init(opts.handler),
       app: nil,
       stream_key: nil,
       server: opts.server,
       buffers_demanded: 0,
       published?: false
     }}
  end

  @impl true
  def handle_info({:tcp, socket, data}, %{use_ssl?: false} = state) when state.socket == socket do
    handle_data(data, state)
  end

  @impl true
  def handle_info({:tcp_closed, socket}, %{use_ssl?: false} = state)
      when state.socket == socket do
    events = [:end_of_stream]
    state = Enum.reduce(events, state, &handle_event/2)

    {:noreply, state}
  end

  @impl true
  def handle_info({:ssl, socket, data}, %{use_ssl?: true} = state) when state.socket == socket do
    handle_data(data, state)
  end

  @impl true
  def handle_info({:ssl_closed, socket}, %{use_ssl?: true} = state) when state.socket == socket do
    events = [:end_of_stream]
    state = Enum.reduce(events, state, &handle_event/2)

    {:noreply, state}
  end

  @impl true
  def handle_info(:control_granted, state) do
    request_data(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:demand_data, how_many_buffers_demanded}, state) do
    state = %{state | buffers_demanded: how_many_buffers_demanded}
    request_data(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(other_msg, state) do
    handler_state = state.handler.handle_info(other_msg, state.handler_state)

    {:noreply, %{state | handler_state: handler_state}}
  end

  defp handle_data(data, state) do
    {messages, message_parser_state} =
      MessageParser.parse_packet_messages(data, state.message_parser_state)

    {message_handler_state, events} =
      MessageHandler.handle_client_messages(messages, state.message_handler_state)

    state = Enum.reduce(events, state, &handle_event/2)

    request_data(state)

    {:noreply,
     %{
       state
       | message_parser_state: message_parser_state,
         message_handler_state: message_handler_state
     }}
  end

  defp handle_event(event, state) do
    # call callbacks
    case event do
      :end_of_stream ->
        new_handler_state = state.handler.handle_end_of_stream(state.handler_state)
        %{state | handler_state: new_handler_state}

      {:set_chunk_size_required, chunk_size} ->
        new_message_parser_state = %{state.message_parser_state | chunk_size: chunk_size}
        %{state | message_parser_state: new_message_parser_state}

      {:data_available, payload} ->
        new_handler_state =
          state.handler.handle_data_available(payload, state.handler_state)

        %{
          state
          | handler_state: new_handler_state,
            buffers_demanded: state.buffers_demanded - 1
        }

      {:connected, connected_msg} ->
        new_handler_state =
          state.handler.handle_connected(connected_msg, state.handler_state)

        %{state | handler_state: new_handler_state, app: connected_msg.app}

      {:published, publish_msg} ->
        send(state.server, {:register_client, state.app, publish_msg.stream_key, self()})

        new_handler_state =
          state.handler.handle_stream_published(publish_msg, state.handler_state)

        %{
          state
          | handler_state: new_handler_state,
            stream_key: publish_msg.stream_key,
            published?: true
        }
    end
  end

  defp request_data(state) do
    if state.buffers_demanded > 0 or state.published? == false do
      if state.use_ssl? do
        :ssl.setopts(state.socket, active: :once)
      else
        :inet.setopts(state.socket, active: :once)
      end
    end
  end
end
