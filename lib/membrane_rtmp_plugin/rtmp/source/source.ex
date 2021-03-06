defmodule Membrane.RTMP.Source do
  @moduledoc """
  Membrane Element for receiving RTMP streams. Acts as a RTMP Server.
  This implementation is limited to only AAC and H264 streams.

  Implementation based on FFmpeg
  """
  use Membrane.Source

  require Membrane.Logger

  alias __MODULE__.Native
  alias Membrane.{AVC, Buffer, Time}

  def_output_pad :audio,
    availability: :always,
    caps: Membrane.AAC.RemoteStream,
    mode: :pull

  def_output_pad :video,
    availability: :always,
    caps: Membrane.H264.RemoteStream,
    mode: :pull

  def_options url: [
                spec: binary(),
                description: """
                URL on which the FFmpeg instance will be created
                """
              ],
              timeout: [
                spec: Time.t() | :infinity,
                default: :infinity,
                description: """
                Time the server will wait for a connection from the client

                Duration given must be a multiply of one second or atom `:infinity`.
                """
              ]

  @impl true
  def handle_init(%__MODULE__{} = opts) do
    {:ok,
     Map.from_struct(opts)
     |> Map.merge(%{provider: nil, stale_frame: nil})}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    pid = Native.start_link(state.url, state.timeout)
    {:ok, %{state | provider: pid}}
  end

  @impl true
  def handle_demand(type, _size, _unit, _ctx, %{stale_frame: {type, buffer}} = state) do
    # There is stale frame, which indicates that that the source was blocked waiting for demand from one of the outputs
    # It now arrived, so we request next frame and output the one that blocked us
    send(state.provider, :get_frame)
    {{:ok, buffer: {type, buffer}}, %{state | stale_frame: nil}}
  end

  @impl true
  def handle_demand(_type, _size, _unit, _ctx, state) do
    {:ok, state}
  end

  @impl true
  def handle_other({Native, :format_info_ready, native_ref}, _ctx, state) do
    actions = get_format_info_actions(native_ref)
    {{:ok, actions}, state}
  end

  @impl true
  def handle_other({Native, :read_frame, {:ok, type, pts, dts, frame}}, ctx, state)
      when ctx.playback_state == :playing do
    pts = Time.milliseconds(pts)
    dts = Time.milliseconds(dts)

    buffer = %Buffer{
      pts: pts,
      dts: dts,
      payload: prepare_payload(type, frame)
    }

    if get_in(ctx.pads, [type, :demand]) > 0 do
      send(state.provider, :get_frame)
      {{:ok, buffer: {type, buffer}}, state}
    else
      # if there is no demand for element of this type so we wait until it appears
      # effectively, it results in source adapting to the slower of the two outputs
      {:ok, %{state | stale_frame: {type, buffer}}}
    end
  end

  @impl true
  def handle_other({Native, :read_frame, :end_of_stream}, _ctx, state) do
    Membrane.Logger.debug("Received end of stream")
    {{:ok, end_of_stream: :audio, end_of_stream: :video}, state}
  end

  @impl true
  def handle_other({Native, :read_frame, {:error, reason}}, _ctx, _state) do
    raise "Fetching of the frame failed. Reason: #{inspect(reason)}"
  end

  @impl true
  def handle_playing_to_prepared(_ctx, state) do
    send(state.provider, :terminate)
    Process.unlink(state.provider)
    {:ok, %{state | provider: nil}}
  end

  defp prepare_payload(:video, payload), do: AVC.Utils.to_annex_b(payload)
  defp prepare_payload(:audio, payload), do: payload

  defp get_format_info_actions(native) do
    [
      get_audio_params(native),
      get_video_params(native)
    ]
    |> Enum.concat()
  end

  defp get_audio_params(native) do
    with {:ok, asc} <- Native.get_audio_params(native) do
      caps = %Membrane.AAC.RemoteStream{
        audio_specific_config: asc
      }

      [caps: {:audio, caps}]
    else
      {:error, _reason} -> []
    end
  end

  defp get_video_params(native) do
    with {:ok, config} <- Native.get_video_params(native) do
      caps = %Membrane.H264.RemoteStream{
        decoder_configuration_record: config,
        stream_format: :byte_stream
      }

      [caps: {:video, caps}]
    else
      {:error, _reason} -> []
    end
  end
end
