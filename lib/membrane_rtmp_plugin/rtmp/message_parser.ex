defmodule Membrane.RTMP.MessageParser do
  @moduledoc false

  require Membrane.Logger

  alias Membrane.RTMP.{Handshake, Header, Message, Messages}

  @enforce_keys [:state_machine, :buffer, :chunk_size, :handshake]
  defstruct @enforce_keys ++ [previous_headers: %{}, current_tx_id: 1]

  @type state_machine_t ::
          :handshake | :connecting | :connected

  @type packet_t :: binary()

  @type t :: %__MODULE__{
          state_machine: state_machine_t(),
          buffer: binary(),
          previous_headers: map(),
          # the chunk size of incoming messages (the other side of connection)
          chunk_size: non_neg_integer(),
          current_tx_id: non_neg_integer(),
          handshake: Handshake.State.t()
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
      handshake: handshake
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

    case read_frame(payload, state.previous_headers, chunk_size) do
      {:error, :need_more_data} ->
        {:need_more_data, %__MODULE__{state | buffer: payload}}

      {header, message, rest} ->
        state = update_state_with_message(state, header, message, rest)

        {header, message, state}
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

    case read_frame(payload, state.previous_headers, chunk_size) do
      {:error, :need_more_data} ->
        {:need_more_data, %__MODULE__{state | buffer: payload}}

      {header, message, rest} ->
        state = update_state_with_message(state, header, message, rest)

        {header, message, state}
    end
  end

  defp read_frame(packet, previous_headers, chunk_size) do
    case Header.deserialize(packet, previous_headers) do
      {%Header{} = header, rest} ->
        chunked_body_size = calculate_chunked_body_size(header, chunk_size)

        case rest do
          <<body::binary-size(chunked_body_size), rest::binary>> ->
            combined_body = combine_body_chunks(body, chunk_size, header)

            message = Message.deserialize_message(header.type_id, combined_body)

            {header, message, rest}

          _rest ->
            {:error, :need_more_data}
        end

      {:error, :need_more_data} = error ->
        error
    end
  end

  defp calculate_chunked_body_size(%Header{body_size: body_size} = header, chunk_size) do
    if body_size > chunk_size do
      # if a message's body is greater than the chunk size then
      # after every chunk_size's bytes there is a 0x03 one byte header that
      # needs to be stripped and is not counted into the body_size
      headers_to_strip = div(body_size - 1, chunk_size)

      # if the initial header contains a extended timestamp then
      # every following chunk will contain the timestamp
      timestamps_to_strip = if header.extended_timestamp?, do: headers_to_strip * 4, else: 0

      body_size + headers_to_strip + timestamps_to_strip
    else
      body_size
    end
  end

  # message's size can exceed the defined chunk size
  # in this case the message gets divided into
  # a sequence of smaller packets separated by the a header type 3 byte
  # (the first 2 bits has to be 0b11)
  defp combine_body_chunks(body, chunk_size, header) do
    if byte_size(body) <= chunk_size do
      body
    else
      do_combine_body_chunks(body, chunk_size, header, [])
    end
  end

  defp do_combine_body_chunks(body, chunk_size, header, acc) do
    case body do
      <<body::binary-size(chunk_size), 0b11::2, _chunk_stream_id::6, timestamp::32, rest::binary>>
      when header.extended_timestamp? and timestamp == header.timestamp ->
        do_combine_body_chunks(rest, chunk_size, header, [acc, body])

      # cut out the header byte (staring with 0b11)
      <<body::binary-size(chunk_size), 0b11::2, _chunk_stream_id::6, rest::binary>> ->
        do_combine_body_chunks(rest, chunk_size, header, [acc, body])

      <<_body::binary-size(chunk_size), header_type::2, _chunk_stream_id::6, _rest::binary>> ->
        Membrane.Logger.warning(
          "Unexpected header type when combining body chunks: #{header_type}"
        )

        IO.iodata_to_binary([acc, body])

      body ->
        IO.iodata_to_binary([acc, body])
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
