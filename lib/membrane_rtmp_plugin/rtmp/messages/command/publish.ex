defmodule Membrane.RTMP.Messages.Publish do
  @moduledoc """
  Defines the RTMP `publish` command.
  """

  @behaviour Membrane.RTMP.Message

  alias Membrane.RTMP.AMF0.Encoder

  @enforce_keys [:stream_key]
  defstruct [:publish_type, tx_id: 0] ++ @enforce_keys

  @type t :: %__MODULE__{
          stream_key: String.t(),
          # NOTE: some RTMP clients like restream.io omit the publishing type
          publish_type: String.t() | nil,
          tx_id: non_neg_integer()
        }

  @name "publish"

  @impl true
  def from_data([@name, tx_id, :null, stream_key, publish_type]) do
    %__MODULE__{tx_id: tx_id, stream_key: stream_key, publish_type: publish_type}
  end

  def from_data([@name, tx_id, :null, stream_key]) do
    %__MODULE__{tx_id: tx_id, stream_key: stream_key}
  end

  defimpl Membrane.RTMP.Messages.Serializer do
    require Membrane.RTMP.Header

    @impl true
    def serialize(%@for{tx_id: tx_id, stream_key: stream_key} = msg) do
      to_encode =
        ["publish", tx_id, :null, stream_key] ++
          if(msg.publish_type, do: [msg.publish_type], else: [])

      Encoder.encode(to_encode)
    end

    @impl true
    def type(%@for{}), do: Membrane.RTMP.Header.type(:amf_command)
  end
end
