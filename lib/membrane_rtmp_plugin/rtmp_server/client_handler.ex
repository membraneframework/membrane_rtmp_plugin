defmodule Membrane.RTMPServer.ClientHandler do
  @moduledoc """
  A behaviour describing the actions that might be taken by the client
  handler in response to different events.
  """

  # It also containts functions responsible for maintaining the lifecycle of the
  # client connection.

  use GenServer

  require Logger
  alias Membrane.RTMP.{Handshake, MessageHandler, MessageParser}

  @typedoc """
  A type representing a module which implements `#{inspect(__MODULE__)}` behaviour.
  """
  @type t :: module()

  @typedoc """
  Type representing the user defined state of the client handler.
  """
  @type state :: any()

  @doc """
  The callback invoked once the client handler is created.
  It should return the initial state of the client handler.
  """
  @callback handle_init(any()) :: state()

  @doc """
  The callback invoked when new piece of data is received from a given client.
  """
  @callback handle_data_available(payload :: binary(), state :: state()) :: state()

  @doc """
  Callback invoked when the RMTP stream is finished.
  """
  @callback handle_delete_stream(state :: state()) :: state()

  @doc """
  Callback invoked when the socket connection is terminated. In normal
  conditions, `handle_delete_stream` is called before this one. If delete_stream
  is not called and connection_closed is, it might just mean that the
  connection was lost (for instance when TCP socket is closed unexpectedly).

  It is up to the users to determined how to handle it in their case.
  """
  @callback handle_connection_closed(state :: state()) :: state()

  @doc """
  The optional callback invoked when the client handler receives a RTMP message.
  """
  @callback handle_rtmp_message(msg :: term(), state()) :: state()

  @doc """
  The callback invoked when the client handler receives a message
  that is not recognized as an internal message of the client handler.
  """
  @callback handle_info(msg :: term(), state()) :: state()

  @optional_callbacks handle_rtmp_message: 2

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

    {:ok,
     %{
       socket: opts.socket,
       use_ssl?: opts.use_ssl?,
       message_parser_state: message_parser_state,
       message_handler_state: message_handler_state,
       handler: nil,
       handler_state: nil,
       app: nil,
       stream_key: nil,
       server: opts.server,
       buffers_demanded: 0,
       published?: false,
       notified_about_client?: false,
       handle_new_client: opts.handle_new_client,
       client_timeout: opts.client_timeout
     }}
  end

  @impl true
  def handle_info({:tcp, socket, data}, %{use_ssl?: false} = state) when state.socket == socket do
    handle_data(data, state)
  end

  @impl true
  def handle_info({:tcp_closed, socket}, %{use_ssl?: false} = state)
      when state.socket == socket do
    events = [:connection_closed]
    state = Enum.reduce(events, state, &handle_event/2)

    {:noreply, state}
  end

  @impl true
  def handle_info({:ssl, socket, data}, %{use_ssl?: true} = state) when state.socket == socket do
    handle_data(data, state)
  end

  @impl true
  def handle_info({:ssl_closed, socket}, %{use_ssl?: true} = state) when state.socket == socket do
    events = [:connection_closed]
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
    state = finish_handshake(state) |> Map.replace!(:buffers_demanded, how_many_buffers_demanded)
    request_data(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({:client_timeout, app, stream_key}, state) do
    if not state.published? do
      Logger.warning("No demand made for client /#{app}/#{stream_key}, terminating connection.")
      :gen_tcp.close(state.socket)
    end

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

    state =
      if message_handler_state.publish_msg != nil and not state.notified_about_client? do
        %{publish_msg: %Membrane.RTMP.Messages.Publish{stream_key: stream_key}} =
          message_handler_state

        if not is_function(state.handle_new_client) do
          raise "handle_new_client is not a function"
        end

        {handler_module, opts} =
          case state.handle_new_client.(self(), state.app, stream_key) do
            {handler_module, opts} -> {handler_module, opts}
            handler_module -> {handler_module, %{}}
          end

        Process.send_after(
          self(),
          {:client_timeout, state.app, stream_key},
          Membrane.Time.as_milliseconds(state.client_timeout, :round)
        )

        %{
          state
          | notified_about_client?: true,
            handler: handler_module,
            handler_state: handler_module.handle_init(opts)
        }
      else
        state
      end

    state = Enum.reduce(events, state, &handle_event/2)

    state =
      if state.notified_about_client? &&
           Kernel.function_exported?(state.handler, :handle_rtmp_message, 2) do
        new_handler_state =
          Enum.reduce(messages, state.handler_state, fn
            {%Membrane.RTMP.Header{}, message}, handler_state when is_map(message) ->
              state.handler.handle_rtmp_message(message, handler_state)

            message, handler_state when is_map(message) ->
              state.handler.handle_rtmp_message(message, handler_state)

            _message, handler_state ->
              handler_state
          end)

        %{state | handler_state: new_handler_state}
      else
        state
      end

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
      :connection_closed ->
        new_handler_state = state.handler.handle_connection_closed(state.handler_state)
        %{state | handler_state: new_handler_state}

      :delete_stream ->
        new_handler_state = state.handler.handle_delete_stream(state.handler_state)
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
        %{state | app: connected_msg.app}

      {:published, publish_msg} ->
        %{
          state
          | stream_key: publish_msg.stream_key,
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

  defp finish_handshake(state) when not state.published? do
    {message_handler_state, events} =
      MessageHandler.send_publish_success(state.message_handler_state)

    state = Enum.reduce(events, state, &handle_event/2)
    %{state | message_handler_state: message_handler_state}
  end

  defp finish_handshake(state), do: state
end
