defmodule Membrane.RTMP.Messages.Connect do
  @moduledoc false

  @behaviour Membrane.RTMP.Message

  alias Membrane.RTMP.AMF.Encoder

  @enforce_keys [:app, :type, :supports_go_away, :flash_version, :swf_url, :tc_url]
  defstruct @enforce_keys ++ [tx_id: 0]

  @type t :: %__MODULE__{
          app: String.t(),
          type: String.t(),
          supports_go_away: boolean(),
          flash_version: String.t(),
          tc_url: String.t(),
          tx_id: non_neg_integer()
        }

  @name "connect"

  @impl true
  def from_data([@name, tx_id, properties]) do
    %{
      "app" => app,
      "type" => type,
      "flashVer" => flash_version,
      "tcUrl" => tc_url
    } = properties

    %__MODULE__{
      app: app,
      type: type,
      supports_go_away: Map.get(properties, "supportsGoAway", false),
      flash_version: flash_version,
      swf_url: Map.get(properties, "swfUrl", tc_url),
      tc_url: tc_url,
      tx_id: tx_id
    }
  end

  defimpl Membrane.RTMP.Messages.Serializer do
    require Membrane.RTMP.Header

    @impl true
    def serialize(%@for{} = msg) do
      Encoder.encode([
        "connect",
        msg.tx_id,
        %{
          "app" => msg.app,
          "type" => msg.type,
          "supportsGoAway" => msg.supports_go_away,
          "flashVer" => msg.flash_version,
          "swfUrl" => msg.swf_url,
          "tcUrl" => msg.tc_url
        }
      ])
    end

    @impl true
    def type(%@for{}), do: Membrane.RTMP.Header.type(:amf_command)
  end
end
