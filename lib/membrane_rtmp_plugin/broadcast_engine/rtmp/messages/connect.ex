defmodule BroadcastEngine.RTMP.Messages.Connect do
  @moduledoc false

  @behaviour BroadcastEngine.RTMP.Message

  alias BroadcastEngine.RTMP.AMFEncoder

  @enforce_keys ~w(app type supports_go_away flash_version swf_url tc_url)a
  defstruct [tx_id: 0] ++ @enforce_keys

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

  defimpl BroadcastEngine.RTMP.Messages.Serializer do
    require BroadcastEngine.RTMP.Header

    alias BroadcastEngine.RTMP.AMFEncoder

    @impl true
    def serialize(%@for{} = msg) do
      AMFEncoder.encode([
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
    def type(%@for{}), do: BroadcastEngine.RTMP.Header.type(:amf_command)
  end
end
