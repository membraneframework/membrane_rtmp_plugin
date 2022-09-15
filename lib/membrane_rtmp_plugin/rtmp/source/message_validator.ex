defmodule Membrane.RTMP.MessageValidator do
  @moduledoc """
  Behaviour module for implementing RTMP Message validators.
  """
  alias Membrane.RTMP.Messages

  defmacro __using__(_) do
    quote do
      @behaviour Membrane.RTMP.MessageValidator

      alias Membrane.RTMP.Messages

      @impl true
      def validate_release_stream(%Messages.ReleaseStream{}), do: :ok
      defoverridable validate_release_stream: 1

      @impl true
      def validate_publish(%Messages.Publish{}), do: :ok
      defoverridable validate_publish: 1

      @impl true
      def validate_set_data_frame(%Messages.SetDataFrame{}), do: :ok
      defoverridable validate_set_data_frame: 1
    end
  end

  @doc """
  Validates the `t:Membrane.RTMP.Messages.ReleaseStream.t/0` message.
  """
  @callback validate_release_stream(Messages.ReleaseStream.t()) :: :ok, {:error, reason}

  @doc """
  Validates the `t:Membrane.RTMP.Messages.Publish.t/0` message.
  """
  @callback validate_publish(Messages.Publish.t()) :: :ok, {:error, reason}

  @doc """
  Validates the `t:Membrane.RTMP.Messages.SetDataFrame.t/0` message.
  """
  @callback validate_set_data_frame(Messages.SetDataFrame.t()) :: :ok, {:error, reason}
end
