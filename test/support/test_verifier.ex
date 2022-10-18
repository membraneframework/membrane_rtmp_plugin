defmodule Membrane.RTMP.Source.TestVerifier do
  @moduledoc false
  use Membrane.RTMP.MessageValidator

  alias Membrane.RTMP.Messages

  @stream_key "ala2137"

  @impl true
  def validate_publish(%Messages.Publish{stream_key: stream_key}) do
    if stream_key == @stream_key do
      :ok
    else
      {:error, "wrong stream key"}
    end
  end
end
