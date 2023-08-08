defmodule Support.TestValidator do
  @moduledoc """
  A MessageValidator implementation. If no stream_key is assigned, all streams
  will be allowed.
  """

  defstruct stream_key: nil
end

defimpl Membrane.RTMP.MessageValidator, for: Support.TestValidator do
  alias Membrane.RTMP.Messages

  @impl true
  def validate_connect(_impl, _message), do: {:ok, "connect success"}

  @impl true
  def validate_publish(%Support.TestValidator{stream_key: nil}, _message),
    do: {:ok, "stream allowed"}

  def validate_publish(%Support.TestValidator{stream_key: accepted_key}, %Messages.Publish{
        stream_key: stream_key
      }) do
    if stream_key == accepted_key do
      {:ok, "correct stream key"}
    else
      {:error, "wrong stream key"}
    end
  end

  @impl true
  def validate_release_stream(_impl, _message), do: {:ok, "release stream success"}

  @impl true
  def validate_set_data_frame(_impl, _message), do: {:ok, "set data frame success"}
end
