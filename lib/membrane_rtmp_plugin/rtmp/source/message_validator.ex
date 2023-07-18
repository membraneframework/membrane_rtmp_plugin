defprotocol Membrane.RTMP.MessageValidator do
  alias Membrane.RTMP.Messages

  @moduledoc """
  Protocol for implementing RTMP Message validators. Allows for verifying some
  of the RTMP messages.
  """

  @type validation_result_t :: {:ok, term()} | {:error, reason :: any()}

  @doc """
  Validates the `t:Membrane.RTMP.Messages.Connect.t/0` message.
  """
  @spec validate_connect(t(), Messages.Connect.t()) :: validation_result_t()
  def validate_connect(impl, message)

  @doc """
  Validates the `t:Membrane.RTMP.Messages.ReleaseStream.t/0` message.
  """
  @spec validate_release_stream(t(), Messages.ReleaseStream.t()) :: validation_result_t()
  def validate_release_stream(impl, message)

  @doc """
  Validates the `t:Membrane.RTMP.Messages.Publish.t/0` message.
  """
  @spec validate_publish(t(), Messages.Publish.t()) :: validation_result_t()
  def validate_publish(impl, message)

  @doc """
  Validates the `t:Membrane.RTMP.Messages.SetDataFrame.t/0` message.
  """
  @spec validate_set_data_frame(t(), Messages.SetDataFrame.t()) :: validation_result_t()
  def validate_set_data_frame(impl, message)

  @doc """
  Validates the `t:Membrane.RTMP.Messages.OnExpectAdditionalMedia.t/0` message.
  """
  @spec validate_on_expect_additional_media(t(), Messages.OnExpectAdditionalMedia.t()) ::
          validation_result_t()
  def validate_on_expect_additional_media(impl, message)

  @doc """
  Validates the `t:Membrane.RTMP.Messages.OnMetaData.t/0` message.
  """
  @spec validate_on_meta_data(t(), Messages.OnMetaData.t()) :: validation_result_t()
  def validate_on_meta_data(impl, message)
end
