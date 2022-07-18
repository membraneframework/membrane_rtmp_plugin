defmodule Membrane.RTMP.Message do
  @moduledoc """
  Behaviour for serializing/deserializing RTMP messages.
  """

  require Membrane.RTMP.Header

  alias Membrane.RTMP.{Header, Messages}

  @type message_data_t :: map() | number() | String.t() | :null

  @type t :: struct()

  @doc """
  Deserializes message binary to a proper struct.
  """
  @callback deserialize(value :: binary()) :: t()

  @doc """
  Create message from arguments list. When the message is a AMF command then
  the first argument is a command name and the second a sequence number.
  """
  @callback from_data([message_data_t()]) :: t()

  @optional_callbacks deserialize: 1, from_data: 1

  @amf_command_to_module %{
    "connect" => Messages.Connect,
    "releaseStream" => Messages.ReleaseStream,
    "FCPublish" => Messages.FCPublish,
    "createStream" => Messages.CreateStream,
    "publish" => Messages.Publish,
    "@setDataFrame" => Messages.SetDataFrame
  }

  @amf_data_to_module %{
    "@setDataFrame" => Messages.SetDataFrame
  }

  @spec deserialize_message(type_id :: integer(), binary()) :: struct()
  def deserialize_message(type_id, payload) do
    case type_id do
      Header.type(:set_chunk_size) ->
        Messages.SetChunkSize.deserialize(payload)

      Header.type(:user_control_message) ->
        Messages.UserControl.deserialize(payload)

      Header.type(:window_acknowledgement_size) ->
        Messages.WindowAcknowledgement.deserialize(payload)

      Header.type(:set_peer_bandwidth) ->
        Messages.SetPeerBandwidth.deserialize(payload)

      Header.type(:amf_data) ->
        message_from_modules(payload, @amf_data_to_module, true)

      Header.type(:amf_command) ->
        message_from_modules(payload, @amf_command_to_module)

      Header.type(:audio_message) ->
        Messages.Audio.deserialize(payload)

      Header.type(:video_message) ->
        Messages.Video.deserialize(payload)
    end
  end

  @spec chunk_payload(binary(), non_neg_integer(), non_neg_integer()) :: iodata()
  def chunk_payload(paylaod, chunk_stream_id, chunk_size)

  def chunk_payload(payload, _chunk_stream_id, chunk_size)
      when byte_size(payload) <= chunk_size do
    payload
  end

  def chunk_payload(payload, chunk_stream_id, chunk_size),
    do: do_chunk_payload(payload, chunk_stream_id, chunk_size, [])

  defp do_chunk_payload(payload, chunk_stream_id, chunk_size, acc)
       when byte_size(payload) > chunk_size do
    <<chunk::binary-size(chunk_size), rest::binary>> = payload

    acc = [<<0b11::2, chunk_stream_id::6>>, chunk | acc]

    do_chunk_payload(rest, chunk_stream_id, chunk_size, acc)
  end

  defp do_chunk_payload(payload, _chunk_stream_id, _chunk_size, acc) do
    [payload | acc]
    |> Enum.reverse()
  end

  defp message_from_modules(payload, mapping, required? \\ false) do
    payload
    |> Membrane.RTMP.AMFParser.parse()
    |> then(fn [command | _rest] = arguments ->
      if required? do
        Map.fetch!(mapping, command)
      else
        Map.get(mapping, command, Messages.Anonymous)
      end
      |> apply(:from_data, [arguments])
    end)
  end
end
