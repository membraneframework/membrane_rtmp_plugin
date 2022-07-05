defprotocol BroadcastEngine.RTMP.Messages.Serializer do
  @moduledoc """
  Protocol for serializing RTMP messages.
  """

  @doc """
  Serializes an RTMP message (without header) into RTMP body binary format.
  """
  @spec serialize(struct()) :: binary()
  def serialize(message)

  @doc """
  Returns the message's type required by the RTMP header.
  """
  @spec type(struct()) :: non_neg_integer()
  def type(message)
end
