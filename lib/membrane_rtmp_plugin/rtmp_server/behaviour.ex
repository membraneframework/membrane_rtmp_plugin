defmodule Membrane.RTMP.Server.Behaviour do

  @type t :: term()

  @callback handle_init() :: t()
  @callback handle_info(msg :: term(), t()) :: t()
  @callback handle_end_of_stream(state :: t()) :: t()
  @callback handle_data_available(payload :: binary(), state :: t()) :: t()
  @callback handle_connected(connected_msg :: Membrane.RTMP.Messages.Connect.t(), state :: t()) :: t()
  @callback handle_stream_published(publish_msg :: Membrane.RTMP.Messages.Publish.t(), state :: t()) :: t()
end
