defmodule Membrane.RTMP.Server.ClientHandlerBehaviour do
  @moduledoc """
  A behaviour describing the actions that might be taken by the client
  handler in response to different events.
  """

  @typedoc """
  Type representing the user defined state of the client handler.
  """
  @type t :: term()

  @doc """
  The callback invoked once the client handler is created.
  It should return the initial state of the client handler.
  """
  @callback handle_init() :: t()

  @doc """
  The callback invoked when the client sends the `Membrane.RTMP.Messages.Connect.t()`
  message.
  """
  @callback handle_connected(connected_msg :: Membrane.RTMP.Messages.Connect.t(), state :: t()) ::
              t()

  @doc """
  The callback invoked when the client sends the `Membrane.RTMP.Messages.Publish.t()`
  message.
  """
  @callback handle_stream_published(
              publish_msg :: Membrane.RTMP.Messages.Publish.t(),
              state :: t()
            ) :: t()

  @doc """
  The callback invoked when new piece of data is received from a given client.
  """
  @callback handle_data_available(payload :: binary(), state :: t()) :: t()

  @doc """
  The callback invoked when the client served by given client handler
  stops sending data.
  (for instance, when the remote client deletes the stream or
  terminates the socket connection)
  """
  @callback handle_end_of_stream(state :: t()) :: t()

  @doc """
  The callback invoked when the client handler receives a message
  that is not recognized as an internal message of the client handler.
  """
  @callback handle_info(msg :: term(), t()) :: t()
end
