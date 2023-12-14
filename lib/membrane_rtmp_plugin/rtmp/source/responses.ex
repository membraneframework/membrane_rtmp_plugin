defmodule Membrane.RTMP.Responses do
  @moduledoc false

  alias Membrane.RTMP.Messages

  @type transaction_id_t :: float() | non_neg_integer()

  @doc """
  Returns a default success response on connect request.
  """
  @spec connection_success(transaction_id_t) :: struct()
  def connection_success(tx_id) do
    %Messages.Anonymous{
      name: "_result",
      tx_id: tx_id,
      properties: [
        %{
          "fmsVer" => "FMS/3,0,1,123",
          "capabilities" => 31.0
        },
        %{
          "level" => "status",
          "code" => "NetConnection.Connect.Success",
          "description" => "Connection succeeded.",
          "objectEncoding" => 0.0
        }
      ]
    }
  end

  @doc """
  Returns a publishment success message.
  """
  @spec publish_success(String.t()) :: struct()
  def publish_success(stream_key) do
    %Messages.Anonymous{
      name: "onStatus",
      tx_id: 0,
      properties: [
        :null,
        %{
          "level" => "status",
          "code" => "NetStream.Publish.Start",
          "description" => "#{stream_key} is now published",
          "details" => stream_key
        }
      ]
    }
  end

  @doc """
  Returns a bandwidth measurement done message.
  """
  @spec on_bw_done() :: struct()
  def on_bw_done() do
    %Messages.Anonymous{
      name: "onBWDone",
      tx_id: 0,
      properties: [
        :null,
        8192.0
      ]
    }
  end

  @doc """
  Returns a default `_result` response with arbitrary body.

  The body can be set by specifying the properties list.
  """
  @spec default_result(transaction_id_t(), [any()]) :: struct()
  def default_result(tx_id, properties \\ []) do
    %Messages.Anonymous{
      name: "_result",
      tx_id: tx_id,
      properties: properties
    }
  end
end
