defmodule Membrane.RTMP.SourceBin do
  @moduledoc """
  Bin responsible for demuxing and parsing an RTMP stream.

  Outputs single audio and video which are ready for further processing with Membrane Elements.
  At this moment only AAC and H264 codecs are supported.

  ## Usage

  The bin requires the RTMP client to be already connected to the socket.
  The socket passed to the bin must be in non-active mode (`active` set to `false`).
  When the `RTMP.Source` is initialized the bin sends `t:Membrane.RTMP.Source.rtmp_source_initialized_t/0` notification.
  Then, the control of the socket should be granted to the `RTMP.Source` with the `:gen_tcp.controlling_process/2`,
  and the `RTMP.Source` will start reading packets from the socket.

  The bin allows for providing custom validator module, that verifies some of the RTMP messages.
  The module has to implement the `Membrane.RTMP.MessageValidator` behaviour.
  """
  use Membrane.Bin

  alias Membrane.{AAC, H264, RTMP}

  def_output_pad :video,
    caps: H264,
    availability: :always,
    mode: :pull,
    demand_unit: :buffers

  def_output_pad :audio,
    caps: AAC,
    availability: :always,
    mode: :pull,
    demand_unit: :buffers

  def_options socket: [
                spec: :gen_tcp.socket(),
                description: """
                Socket, on which the bin will receive RTMP stream. The socket will be passed to the `RTMP.Source`.
                The socket must be already connected to the RTMP client and be in non-active mode (`active` set to `false`).
                """
              ],
              validator: [
                spec: Membrane.RTMP.StreamValidator,
                description: """
                A Module implementing `Membrane.RTMP.MessageValidator` behaviour, used for validating the stream.
                """,
                default: Membrane.RTMP.DefaultValidator
              ]

  @impl true
  def handle_init(%__MODULE__{} = opts) do
    spec = %ParentSpec{
      children: %{
        src: %RTMP.Source{socket: opts.socket, validator: opts.validator},
        demuxer: Membrane.FLV.Demuxer,
        video_parser: %Membrane.H264.FFmpeg.Parser{
          alignment: :au,
          attach_nalus?: true,
          skip_until_keyframe?: true
        },
        audio_parser: %Membrane.AAC.Parser{
          in_encapsulation: :none,
          out_encapsulation: :none
        }
      },
      links: [
        link(:src) |> to(:demuxer),
        #
        link(:demuxer)
        |> via_out(Pad.ref(:audio, 0))
        |> to(:audio_parser)
        |> to_bin_output(:audio),
        #
        link(:demuxer)
        |> via_out(Pad.ref(:video, 0))
        |> to(:video_parser)
        |> to_bin_output(:video)
      ]
    }

    {{:ok, spec: spec}, %{}}
  end

  @impl true
  def handle_notification(
        {:rtmp_source_initialized, _socket, _pid} = notification,
        :src,
        _ctx,
        state
      ) do
    {{:ok, [notify: notification]}, state}
  end

  def handle_notification(
        {:rtmp_stream_validation_failed, _socket, _reason} = notification,
        :src,
        _ctx,
        state
      ) do
    {{:ok, [notify: notification]}, state}
  end

  @spec pass_control(:gen_tcp.socket(), pid) :: :ok | {:error, atom}
  def pass_control(socket, source) do
    :gen_tcp.controlling_process(socket, source)
  end
end
