defmodule Membrane.RTMP.MessageParser do
  @moduledoc false

  require Membrane.Logger

  alias Membrane.RTMP.{Handshake, Header, Message, Messages}

  @enforce_keys [:state_machine, :buffer, :chunk_size, :handshake]
  defstruct @enforce_keys ++ [previous_headers: %{}, current_tx_id: 1, partial_messages: %{}]

  @type state_machine_t ::
          :handshake | :connecting | :connected

  @type packet_t :: binary()

  @type partial_message :: %{
          header: Header.t(),
          body_chunks: [binary()],
          bytes_received: non_neg_integer()
        }

  @type t :: %__MODULE__{
          state_machine: state_machine_t(),
          buffer: binary(),
          previous_headers: map(),
          # the chunk size of incoming messages (the other side of connection)
          chunk_size: non_neg_integer(),
          current_tx_id: non_neg_integer(),
          handshake: Handshake.State.t(),
          # tracks partial messages per chunk stream ID to support interleaving
          partial_messages: %{non_neg_integer() => partial_message()}
        }

  @doc """
  Initializes the RTMP MessageParser.

  The MessageParser starts in a handshake process which is dictated by the passed
  handshake state.
  """
  @spec init(Handshake.State.t(), Keyword.t()) :: t()
  def init(handshake, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, 128)

    %__MODULE__{
      state_machine: :handshake,
      buffer: <<>>,
      # previous header for each of the stream chunks
      previous_headers: %{},
      chunk_size: chunk_size,
      handshake: handshake,
      partial_messages: %{}
    }
  end

  @doc """
  Parses RTMP messages from a packet.

  The RTMP connection is based on TCP therefore we are operating on a continuous stream of bytes.
  In such case packets received on TCP sockets may contain a partial RTMP packet or several full packets.

  `MessageParser` is already able to request more data if packet is incomplete but it is not aware
  if its current buffer contains more than one message, therefore we need to call the `&MessageParser.handle_packet/2`
  as long as we decide to receive more messages (before starting to relay media packets).

  Once we hit `:need_more_data` the function returns the list of parsed messages and the message_parser then is ready
  to receive more data to continue with emitting new messages.
  """
  @spec parse_packet_messages(packet :: binary(), message_parser :: struct(), [{any(), any()}]) ::
          {[Message.t()], message_parser :: struct()}
  def parse_packet_messages(packet, message_parser, messages \\ [])

  def parse_packet_messages(<<>>, %{buffer: <<>>} = message_parser, messages) do
    {Enum.reverse(messages), message_parser}
  end

  def parse_packet_messages(packet, message_parser, messages) do
    case handle_packet(packet, message_parser) do
      {header, message, message_parser} ->
        parse_packet_messages(<<>>, message_parser, [{header, message} | messages])

      {:need_more_data, message_parser} ->
        {Enum.reverse(messages), message_parser}

      {:handshake_done, message_parser} ->
        parse_packet_messages(<<>>, message_parser, messages)

      {%Handshake.Step{} = step, message_parser} ->
        parse_packet_messages(<<>>, message_parser, [{nil, step} | messages])
    end
  end

  @doc """
  Generates a list of the following transaction tx_ids.

  Updates the internal transaction id counter so that
  the MessageParser can be further used for generating the next ones.
  """
  @spec generate_tx_ids(t(), n :: non_neg_integer()) :: {list(non_neg_integer()), t()}
  def generate_tx_ids(%__MODULE__{current_tx_id: tx_id} = message_parser, n) when n > 0 do
    tx_ids = Enum.to_list(tx_id..(tx_id + n - 1))

    {tx_ids, %{message_parser | current_tx_id: tx_id + n}}
  end

  @spec handle_packet(packet_t(), t()) ::
          {Handshake.Step.t() | :need_more_data | :handshake_done | binary(), t()}
          | {Header.t(), Message.t(), t()}
  def handle_packet(packet, state)

  def handle_packet(
        packet,
        %{state_machine: :connected, buffer: buffer, chunk_size: chunk_size} = state
      ) do
    payload = buffer <> packet

    case read_frame(payload, state.previous_headers, chunk_size, state.partial_messages) do
      {:error, :need_more_data} ->
        {:need_more_data, %__MODULE__{state | buffer: payload}}

      {:error, :invalid_chunk_stream} ->
        # Invalid chunk stream detected, likely due to corrupted data
        # Clear buffer and partial messages to try to recover
        Membrane.Logger.error(
          "Invalid chunk stream detected. Clearing buffers to attempt recovery."
        )

        {:need_more_data, %__MODULE__{state | buffer: <<>>, partial_messages: %{}}}

      {:complete, header, message, rest, new_partial_messages} ->
        # Complete message - update_state_with_message will handle previous_headers
        state =
          update_state_with_message(state, header, message, rest)
          |> Map.put(:partial_messages, new_partial_messages)

        {header, message, state}

      {:partial, rest, new_partial_messages, new_previous_headers} ->
        # Partial message - update previous_headers if needed
        new_state =
          if new_previous_headers == :no_change do
            %__MODULE__{state | buffer: rest, partial_messages: new_partial_messages}
          else
            %__MODULE__{
              state
              | buffer: rest,
                partial_messages: new_partial_messages,
                previous_headers: new_previous_headers
            }
          end

        # Continue processing if there's more data in the buffer
        # This handles the case where multiple chunks arrive in the same packet
        if rest != <<>> do
          handle_packet(<<>>, new_state)
        else
          {:need_more_data, new_state}
        end
    end
  end

  def handle_packet(
        packet,
        %{state_machine: :handshake, buffer: buffer, handshake: handshake} = state
      ) do
    payload = buffer <> packet

    step_size = Handshake.expects_bytes(handshake)

    case payload do
      <<step_data::binary-size(step_size), rest::binary>> ->
        case Handshake.handle_step(step_data, handshake) do
          {:continue_handshake, step, handshake} ->
            # continue with the handshake
            {step, %__MODULE__{state | buffer: rest, handshake: handshake}}

          # the handshake is done but with last step to return
          {:handshake_finished, step, _handshake} ->
            {step,
             %__MODULE__{
               state
               | buffer: rest,
                 handshake: nil,
                 state_machine: fsm_transition(:handshake)
             }}

          # the handshake is done without further steps
          {:handshake_finished, _handshake} ->
            {:handshake_done,
             %__MODULE__{
               state
               | buffer: rest,
                 handshake: nil,
                 state_machine: fsm_transition(:handshake)
             }}

          {:error, {:invalid_handshake_step, step_type}} ->
            raise "Invalid handshake step: #{step_type}"
        end

      _payload ->
        {:need_more_data, %__MODULE__{state | buffer: payload}}
    end
  end

  def handle_packet(
        packet,
        %{state_machine: :connecting, buffer: buffer, chunk_size: chunk_size} = state
      ) do
    payload = buffer <> packet

    case read_frame(payload, state.previous_headers, chunk_size, state.partial_messages) do
      {:error, :need_more_data} ->
        {:need_more_data, %__MODULE__{state | buffer: payload}}

      {:error, :invalid_chunk_stream} ->
        # Invalid chunk stream detected, likely due to corrupted data
        # Clear buffer and partial messages to try to recover
        Membrane.Logger.error(
          "Invalid chunk stream detected. Clearing buffers to attempt recovery."
        )

        {:need_more_data, %__MODULE__{state | buffer: <<>>, partial_messages: %{}}}

      {:complete, header, message, rest, new_partial_messages} ->
        # Complete message - update_state_with_message will handle previous_headers
        state =
          update_state_with_message(state, header, message, rest)
          |> Map.put(:partial_messages, new_partial_messages)

        {header, message, state}

      {:partial, rest, new_partial_messages, new_previous_headers} ->
        # Partial message - update previous_headers if needed
        new_state =
          if new_previous_headers == :no_change do
            %__MODULE__{state | buffer: rest, partial_messages: new_partial_messages}
          else
            %__MODULE__{
              state
              | buffer: rest,
                partial_messages: new_partial_messages,
                previous_headers: new_previous_headers
            }
          end

        # Continue processing if there's more data in the buffer
        # This handles the case where multiple chunks arrive in the same packet
        if rest != <<>> do
          handle_packet(<<>>, new_state)
        else
          {:need_more_data, new_state}
        end
    end
  end

  defp read_frame(packet, previous_headers, chunk_size, partial_messages) do
    case Header.deserialize(packet, previous_headers) do
      {%Header{} = header, rest} ->
        # Determine if this is a continuation chunk
        # A chunk is a continuation if we have a partial message buffered for this chunk_stream_id
        is_continuation = Map.has_key?(partial_messages, header.chunk_stream_id)

        if is_continuation do
          # This is a continuation of an existing partial message
          continue_partial_message(header, rest, chunk_size, partial_messages, previous_headers)
        else
          # This is a new message (Type 0, 1, 2, or Type 3 for a new chunk stream)
          start_new_message(header, rest, chunk_size, partial_messages, previous_headers)
        end

      {:error, {:missing_previous_header, chunk_stream_id, header_type}} ->
        Membrane.Logger.warning(
          "Received #{header_type} header for unknown chunk_stream_id: #{chunk_stream_id}. " <>
            "This may indicate chunk interleaving issue or corrupted stream data. Skipping."
        )

        {:error, :invalid_chunk_stream}

      {:error, :need_more_data} = error ->
        error
    end
  end

  defp start_new_message(header, rest, chunk_size, partial_messages, previous_headers) do
    # Calculate how many bytes to read for this chunk
    bytes_to_read = min(header.body_size, chunk_size)

    case rest do
      <<chunk::binary-size(bytes_to_read), rest::binary>> ->
        if bytes_to_read >= header.body_size do
          # Message is complete in a single chunk
          # Don't update previous_headers here - update_state_with_message will handle it
          message = Message.deserialize_message(header.type_id, chunk)
          {:complete, header, message, rest, partial_messages}
        else
          # Message spans multiple chunks, store as partial
          # Also update previous_headers so Type 3 continuation headers can be deserialized
          partial = %{
            header: header,
            body_chunks: [chunk],
            bytes_received: bytes_to_read
          }

          new_partial_messages = Map.put(partial_messages, header.chunk_stream_id, partial)
          new_previous_headers = Map.put(previous_headers, header.chunk_stream_id, header)
          {:partial, rest, new_partial_messages, new_previous_headers}
        end

      _rest ->
        {:error, :need_more_data}
    end
  end

  defp continue_partial_message(header, rest, chunk_size, partial_messages, _previous_headers) do
    partial = Map.get(partial_messages, header.chunk_stream_id)

    if partial == nil do
      # This shouldn't happen - Type 3 header for unknown chunk_stream_id
      # This will be caught by the missing_previous_header error
      {:error, :invalid_chunk_stream}
    else
      # Calculate remaining bytes for this message
      remaining_bytes = partial.header.body_size - partial.bytes_received
      bytes_to_read = min(remaining_bytes, chunk_size)

      case rest do
        <<chunk::binary-size(bytes_to_read), rest::binary>> ->
          new_bytes_received = partial.bytes_received + bytes_to_read
          new_body_chunks = [partial.body_chunks, chunk]

          if new_bytes_received >= partial.header.body_size do
            # Message is now complete
            # Don't update previous_headers here - update_state_with_message will handle it
            complete_body = IO.iodata_to_binary(new_body_chunks)
            message = Message.deserialize_message(partial.header.type_id, complete_body)
            new_partial_messages = Map.delete(partial_messages, header.chunk_stream_id)

            # Use the original header from when the message started
            {:complete, partial.header, message, rest, new_partial_messages}
          else
            # Still partial, continue buffering
            # Keep previous_headers as is (already has the header from first chunk)
            updated_partial = %{
              partial
              | body_chunks: new_body_chunks,
                bytes_received: new_bytes_received
            }

            new_partial_messages =
              Map.put(partial_messages, header.chunk_stream_id, updated_partial)

            # Return :no_change for previous_headers to indicate no update needed
            {:partial, rest, new_partial_messages, :no_change}
          end

        _rest ->
          {:error, :need_more_data}
      end
    end
  end

  # in case of client interception the Publish message indicates successful connection
  # (unless proxy temrinates the connection) and medai can be relayed
  defp message_fsm_transition(%Messages.Publish{}), do: :connected

  # when receiving audio or video messages, we are remaining in connected state
  defp message_fsm_transition(%Messages.Audio{}), do: :connected
  defp message_fsm_transition(%Messages.Video{}), do: :connected

  # in case of server interception the `NetStream.Publish.Start` indicates
  # that the connection has been successful and media can be relayed
  defp message_fsm_transition(%Messages.Anonymous{
         name: "onStatus",
         properties: [:null, %{"code" => "NetStream.Publish.Start"}]
       }),
       do: :connected

  defp message_fsm_transition(_message), do: :connecting

  defp fsm_transition(:handshake), do: :connecting

  defp update_state_with_message(state, header, message, rest) do
    updated_headers = Map.put(state.previous_headers, header.chunk_stream_id, header)

    %__MODULE__{
      state
      | chunk_size: maybe_update_chunk_size(message, state),
        previous_headers: updated_headers,
        buffer: rest,
        state_machine: message_fsm_transition(message)
    }
  end

  defp maybe_update_chunk_size(%Messages.SetChunkSize{chunk_size: size}, _state), do: size
  defp maybe_update_chunk_size(_size, %{chunk_size: size}), do: size
end
