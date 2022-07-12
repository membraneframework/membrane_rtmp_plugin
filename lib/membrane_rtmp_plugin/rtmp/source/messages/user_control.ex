defmodule Membrane.RTMP.Messages.UserControl do
  @moduledoc false

  @behaviour Membrane.RTMP.Message

  @enforce_keys [:event_type, :data]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          event_type: non_neg_integer(),
          data: binary()
        }

  @impl true
  def deserialize(<<event_type::16, data::binary>>) do
    %__MODULE__{event_type: event_type, data: data}
  end

  defimpl Membrane.RTMP.Messages.Serializer do
    require Membrane.RTMP.Header

    @impl true
    def serialize(%@for{event_type: event_type, data: data}) do
      <<event_type::16, data::binary>>
    end

    @impl true
    def type(%@for{}), do: Membrane.RTMP.Header.type(:user_control_message)
  end
end
