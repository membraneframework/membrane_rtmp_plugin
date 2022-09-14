defmodule Membrane.RTMP.Interceptor do
  @moduledoc """
  #{inspect(__MODULE__)} is responsible for parsing
  all the RTMP connection information until the media packets start to flow.

  The main use-case is to parse things such as `stream_key` or stream
  parameters information being represented by RTMP commands.
  """

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
          #  the chunk size of incoming messages (the other side of connection)
          chunk_size: non_neg_integer(),
          current_tx_id: non_neg_integer(),
          handshake: Handshake.State.t()
        }

  @doc """
  Initializes the RTMP interceptor.

  The interceptor starts in a handshake process which is dictated by the passed
  handshake state.
  """
  @spec init(Handshake.State.t(), Keyword.t()) :: t()
  def init(handshake, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, 128)

    %__MODULE__{
      state_machine: :handshake,
      buffer: <<>>,
      # previous_headers keeps previous header for each of the stream chunks
      previous_headers: %{},
      chunk_size: chunk_size,
      handshake: handshake
    }
  end

  @doc """
  Generates a list of the following transaction tx_ids.

  Updates the internal transaction id counter so that
  the interceptor can be further used for generating the next ones.
  """
  @spec generate_tx_ids(t(), n :: non_neg_integer()) :: {list(non_neg_integer()), t()}
  def generate_tx_ids(%__MODULE__{current_tx_id: tx_id} = interceptor, n) when n > 0 do
    tx_ids = Enum.map(1..n, &(tx_id + &1 - 1))

    {tx_ids, %{interceptor | current_tx_id: tx_id + n}}
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
      :need_more_data ->
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

    if byte_size(payload) >= step_size do
      <<step_data::binary-size(step_size), rest::binary>> = payload

      case Handshake.handle_step(step_data, handshake) do
        {:cont, step, handshake} ->
          # continue with the handshake
          {step, %__MODULE__{state | buffer: rest, handshake: handshake}}

        # the handshake is done but with last step to return
        {:ok, step, _handshake} ->
          {step,
           %__MODULE__{
             state
             | buffer: rest,
               handshake: nil,
               state_machine: fsm_transition(:handshake)
           }}

        # the handshake is done without further steps
        {:ok, _handshake} ->
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
    else
      {:need_more_data, %__MODULE__{state | buffer: payload}}
    end
  end

  def handle_packet(
        packet,
        %{state_machine: :connecting, buffer: buffer, chunk_size: chunk_size} = state
      ) do
    payload = buffer <> packet

    case read_frame(payload, state.previous_headers, chunk_size) do
      :need_more_data ->
        {:need_more_data, %__MODULE__{state | buffer: payload}}

      {header, message, rest} ->
        state = update_state_with_message(state, header, message, rest)

        {header, message, state}
    end
  end

  defp read_frame(packet, previous_headers, chunk_size) do
    {%Header{body_size: body_size} = header, rest} = Header.deserialize(packet, previous_headers)

    chunked_body_size =
      if body_size > chunk_size do
        # if a message's body is greater than the chunk size then
        # after every chunk_size's bytes there is a 0x03 one byte header that
        # needs to be stripped and is not counted into the body_size
        headers_to_strip = div(body_size - 1, chunk_size)

        body_size + headers_to_strip
      else
        body_size
      end

    if chunked_body_size <= byte_size(rest) do
      <<body::binary-size(chunked_body_size), rest::binary>> = rest

      combined_body = combine_body_chunks(body, chunk_size)

      message = Message.deserialize_message(header.type_id, combined_body)

      {header, message, rest}
    else
      :need_more_data
    end
  end

  # message's size can exceed the defined chunk size
  # in this case the message gets divided into
  # a sequence of smaller packets separated by the a header type 3 byte
  # (the first 2 bits has to be 0b11)
  defp combine_body_chunks(body, chunk_size) do
    if byte_size(body) <= chunk_size do
      body
    else
      do_combine_body_chunks(body, chunk_size, <<>>)
    end
  end

  defp do_combine_body_chunks(body, chunk_size, acc) when byte_size(body) <= chunk_size do
    acc <> body
  end

  defp do_combine_body_chunks(body, chunk_size, acc) do
    # cut out the header byte (staring with 0b11)
    <<body::binary-size(chunk_size), 0b11::2, _chunk_stream_id::6, rest::binary>> = body

    do_combine_body_chunks(rest, chunk_size, acc <> body)
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
