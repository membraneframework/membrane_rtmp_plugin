defmodule Membrane.RTMP.Messages.Connect do
  @moduledoc """
  Defines the RTMP `connect` command.
  """

  @behaviour Membrane.RTMP.Message

  alias Membrane.RTMP.AMF.Encoder

  @enforce_keys [:app, :tc_url]
  defstruct @enforce_keys ++
              [
                :flash_version,
                :swf_url,
                :fpad,
                :audio_codecs,
                :video_codecs,
                :video_function,
                :page_url,
                :object_encoding,
                extra: %{},
                tx_id: 0
              ]

  @type t :: %__MODULE__{
          app: String.t(),
          tc_url: String.t(),
          flash_version: String.t() | nil,
          swf_url: String.t() | nil,
          fpad: boolean() | nil,
          audio_codecs: float() | nil,
          video_codecs: float() | nil,
          video_function: float() | nil,
          page_url: String.t() | nil,
          object_encoding: float() | nil,
          extra: %{optional(String.t()) => any()},
          tx_id: float() | non_neg_integer()
        }

  @keys_to_attributes %{
    app: "app",
    tc_url: "tcUrl",
    flash_version: "flashVer",
    swf_url: "swfUrl",
    fpad: "fpad",
    audio_codecs: "audioCodecs",
    video_codecs: "videoCodecs",
    video_function: "videoFunction",
    page_url: "pageUrl",
    object_encoding: "objectEncoding"
  }

  @attributes_to_keys Map.new(@keys_to_attributes, fn {key, attribute} -> {attribute, key} end)

  @name "connect"

  @impl true
  def from_data([@name, tx_id, properties]) do
    # We take keys according to RFC, but preserve all extra ones
    # https://github.com/melpon/rfc/blob/master/rtmp.md#7211-connect
    {rfc, extra} = Map.split(properties, Map.keys(@attributes_to_keys))

    rfc
    |> Map.new(fn {string_key, value} -> {Map.fetch!(@attributes_to_keys, string_key), value} end)
    |> Map.merge(%{tx_id: tx_id, extra: extra})
    |> then(&struct!(__MODULE__, &1))
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = message) do
    message
    |> Map.take(Map.keys(@keys_to_attributes))
    |> Map.new(fn {key, value} -> {Map.fetch!(@keys_to_attributes, key), value} end)
    |> Map.merge(message.extra)
  end

  defimpl Membrane.RTMP.Messages.Serializer do
    require Membrane.RTMP.Header

    @impl true
    def serialize(%@for{} = msg) do
      msg
      |> @for.to_map()
      |> then(&Encoder.encode(["connect", msg.tx_id, &1]))
    end

    @impl true
    def type(%@for{}), do: Membrane.RTMP.Header.type(:amf_command)
  end
end
