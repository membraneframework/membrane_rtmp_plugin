defmodule Membrane.RTMP.MessageValidator do
  @moduledoc """
  Behaviour module for implementing RTMP Message validators.

  Allows for verifying some of the RTMP messages. To create a custom validator module `use MessageValidator`
  and override the specific callbacks. By default all other messages will be allowed.
  """
  alias Membrane.RTMP.Messages

  defmacro __using__(_) do
    quote do
      @behaviour Membrane.RTMP.MessageValidator

      alias Membrane.RTMP.Messages

      @impl true
      def validate_release_stream(%Messages.ReleaseStream{}), do: :ok

      @impl true
      def validate_publish(%Messages.Publish{}), do: :ok

      @impl true
      def validate_set_data_frame(%Messages.SetDataFrame{}), do: :ok

      defoverridable Membrane.RTMP.MessageValidator
    end
  end

  @doc """
  Validates the `t:Membrane.RTMP.Messages.ReleaseStream.t/0` message.
  """
  @callback validate_release_stream(Messages.ReleaseStream.t()) :: :ok | {:error, any()}

  @doc """
  Validates the `t:Membrane.RTMP.Messages.Publish.t/0` message.
  """
  @callback validate_publish(Messages.Publish.t()) :: :ok | {:error, any()}

  @doc """
  Validates the `t:Membrane.RTMP.Messages.SetDataFrame.t/0` message.
  """
  @callback validate_set_data_frame(Messages.SetDataFrame.t()) :: :ok | {:error, any()}
end
