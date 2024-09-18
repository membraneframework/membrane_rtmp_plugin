defmodule Membrane.RTMP.Messages.SetPeerBandwidth do
  @moduledoc false

  @behaviour Membrane.RTMP.Message

  @enforce_keys [:size]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          size: non_neg_integer()
        }

  @limit_type 0x02

  @impl true
  def deserialize(<<size::32, @limit_type::8>>) do
    %__MODULE__{size: size}
  end

  defimpl Membrane.RTMP.Messages.Serializer do
    require Membrane.RTMP.Header

    @impl true
    def serialize(%@for{size: size}) do
      <<size::32, 0x02::8>>
    end

    @impl true
    def type(%@for{}), do: Membrane.RTMP.Header.type(:set_peer_bandwidth)
  end
end
