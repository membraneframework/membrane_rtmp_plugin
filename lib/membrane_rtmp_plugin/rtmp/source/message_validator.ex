defmodule Membrane.RTMP.MessageValidator do
  @moduledoc """
  Behaviour module for implementing RTMP Message validators.

  Allows for verifying some of the RTMP messages. To create a custom validator module `use MessageValidator`
  and override the specific callbacks. By default all other messages will be allowed.
  """
  alias Membrane.RTMP.Messages

  @type validation_result_t :: {:ok, message :: any()} | {:error, reason :: any()}

  defmacro __using__(_) do
    quote do
      @behaviour Membrane.RTMP.MessageValidator

      alias Membrane.RTMP.Messages

      @impl true
      def validate_release_stream(%Messages.ReleaseStream{}), do: {:ok, "release stream success"}

      @impl true
      def validate_publish(%Messages.Publish{}), do: {:ok, "publish success"}

      @impl true
      def validate_set_data_frame(%Messages.SetDataFrame{}), do: {:ok, "set data frame success"}
      defoverridable Membrane.RTMP.MessageValidator
    end
  end

  @doc """
  Validates the `t:Membrane.RTMP.Messages.ReleaseStream.t/0` message.
  """
  @callback validate_release_stream(Messages.ReleaseStream.t()) :: validation_result_t()

  @doc """
  Validates the `t:Membrane.RTMP.Messages.Publish.t/0` message.
  """
  @callback validate_publish(Messages.Publish.t()) :: validation_result_t()

  @doc """
  Validates the `t:Membrane.RTMP.Messages.SetDataFrame.t/0` message.
  """
  @callback validate_set_data_frame(Messages.SetDataFrame.t()) :: validation_result_t()
end
