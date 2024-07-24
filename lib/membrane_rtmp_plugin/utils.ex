defmodule Membrane.RTMP.Utils do
  @moduledoc """
  Utility functions
  """

  @doc """
  Extracts ssl, port, app and stream_key from url.
  """
  @spec parse_url(url :: String.t()) :: {boolean(), integer(), String.t(), String.t()}
  def parse_url(url) do
    uri = URI.parse(url)
    port = uri.port

    {app, stream_key} =
      case String.trim_leading(uri.path, "/") |> String.trim_trailing("/") |> String.split("/") do
        [app, stream_key] -> {app, stream_key}
        [app] -> {app, ""}
      end

    use_ssl? =
      case uri.scheme do
        "rtmp" -> false
        "rtmps" -> true
      end

    {use_ssl?, port, app, stream_key}
  end
end
