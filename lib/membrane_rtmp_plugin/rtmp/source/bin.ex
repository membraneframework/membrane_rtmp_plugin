defmodule Membrane.RTMP.SourceBin do
  @moduledoc """
  Bin responsible for demuxing and parsing an RTMP stream.

  Outputs single audio and video which are ready for further processing with Membrane Elements.
  At this moment only AAC and H264 codecs are supported.
  """
  use Membrane.Bin

  alias Membrane.{AAC, H264, RTMP}

  def_output_pad :video,
    accepted_format: H264,
    availability: :always

  def_output_pad :audio,
    accepted_format: AAC,
    availability: :always

  def_options app: [], stream_key: [], server: []

  @impl true
  def handle_init(_ctx, %__MODULE__{} = opts) do
    structure = [
      child(:src, %RTMP.Source{
        server: opts.server,
        app: opts.app,
        stream_key: opts.stream_key
      })
      |> child(:demuxer, Membrane.FLV.Demuxer),
      child(:audio_parser, %Membrane.AAC.Parser{
        out_encapsulation: :none
      }),
      child(:video_parser, Membrane.H264.Parser),
      #
      get_child(:demuxer)
      |> via_out(Pad.ref(:audio, 0))
      |> get_child(:audio_parser)
      |> bin_output(:audio),
      #
      get_child(:demuxer)
      |> via_out(Pad.ref(:video, 0))
      |> get_child(:video_parser)
      |> bin_output(:video)
    ]

    {[spec: structure], %{}}
  end

  @impl true
  def handle_child_notification(
        {type, _socket, _pid} = notification,
        :src,
        _ctx,
        state
      )
      when type in [:socket_control_needed, :ssl_socket_control_needed] do
    {[notify_parent: notification], state}
  end

  def handle_child_notification(
        {type, _stage, _reason} = notification,
        :src,
        _ctx,
        state
      )
      when type in [:stream_validation_success, :stream_validation_error] do
    {[notify_parent: notification], state}
  end

  @doc """
  Passes the control of the socket to the `source`.

  To succeed, the executing process must be in control of the socket, otherwise `{:error, :not_owner}` is returned.
  """
  @spec pass_control(:gen_tcp.socket(), pid()) :: :ok | {:error, atom()}
  def pass_control(socket, source) do
    :gen_tcp.controlling_process(socket, source)
  end

  @doc """
  Passes the control of the ssl socket to the `source`.

  To succeed, the executing process must be in control of the socket, otherwise `{:error, :not_owner}` is returned.
  """
  @spec secure_pass_control(:ssl.sslsocket(), pid()) :: :ok | {:error, any()}
  def secure_pass_control(socket, source) do
    :ssl.controlling_process(socket, source)
  end
end
