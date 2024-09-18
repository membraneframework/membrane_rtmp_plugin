defprotocol Membrane.RTMP.Messages.Serializer do
  @moduledoc false

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
