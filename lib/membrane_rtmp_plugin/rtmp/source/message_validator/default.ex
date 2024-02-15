defmodule Membrane.RTMP.MessageValidator.Default do
  @moduledoc """
  Default implementation of the MessageValidator protocol which allows every
  incoming stream.
  """
  defstruct []
end

defimpl Membrane.RTMP.MessageValidator, for: Membrane.RTMP.MessageValidator.Default do
  @impl true
  def validate_connect(_impl, _message), do: {:ok, "connect success"}

  @impl true
  def validate_release_stream(_impl, _message), do: {:ok, "release stream success"}

  @impl true
  def validate_publish(_impl, _message), do: {:ok, "validate publish success"}

  @impl true
  def validate_set_data_frame(_impl, _message), do: {:ok, "set data frame success"}

  @impl true
  def validate_on_expect_additional_media(_impl, _message),
    do: {:ok, "on expect additional media success"}

  @impl true
  def validate_on_meta_data(_impl, _message), do: {:ok, "on meta data success"}
end
