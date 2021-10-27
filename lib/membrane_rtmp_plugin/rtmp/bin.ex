defmodule Membrane.RTMP.Bin do
  @moduledoc """
  Bin responsible for spawning new RTMP server.

  It will receive RTMP stream from the client, parse it and demux FLV outputing single audio and video which are ready for further processing with Membrane Elements.
  At this moment only AAC and H264 codecs are support
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

  def_options port: [
                spec: 1..65_535,
                description: "Port on which the server will listen"
              ],
              local_ip: [
                spec: binary(),
                default: "127.0.0.1",
                description:
                  "IP address on which the server will listen. This is useful if you have more than one network interface"
              ],
              timeout: [
                spec: Time.t() | :infinity,
                default: :infinity,
                description: """
                Time during which the connection with the client must be established before handle_prepared_to_playing fails.

                Duration given must be a multiply of one second or atom `:infinity`.
                """
              ]

  @impl true
  def handle_init(%__MODULE__{} = options) do
    url = "rtmp://#{options.local_ip}:#{options.port}"
    source = %RTMP.Source{url: url, timeout: options.timeout}

    spec = %ParentSpec{
      children: %{
        src: source,
        video_parser: %Membrane.H264.FFmpeg.Parser{
          framerate: {30, 1},
          alignment: :au,
          attach_nalus?: true,
          skip_until_keyframe?: true
        }
      },
      links: [
        link(:src) |> via_out(:audio) |> to_bin_output(:audio),
        link(:src) |> via_out(:video) |> to(:video_parser) |> to_bin_output(:video)
      ]
    }

    {{:ok, spec: spec}, %{}}
  end
end
