# After running this script, you can access the server at rtmp://localhost:5000
# You can use FFmpeg to stream to it
# ffmpeg -re -i test/fixtures/testsrc.flv -f flv -c:v copy -c:a copy rtmp://localhost:5000

Mix.install([
  {:membrane_core, "~> 0.10"},
  {:membrane_rtmp_plugin, path: __DIR__ |> Path.join("../") |> Path.expand()},
  :membrane_file_plugin,
  :membrane_mp4_plugin,
  :membrane_flv_plugin,
  :membrane_aac_plugin
])

defmodule Pipeline do
  use Membrane.Pipeline

  @output_file "received.flv"

  @impl true
  def handle_init(socket: socket, parent: parent) do
    spec = %ParentSpec{
      children: %{
        source: %Membrane.RTMP.SourceBin{
          socket: socket
        },
        video_payloader: Membrane.MP4.Payloader.H264,
        muxer: Membrane.FLV.Muxer,
        sink: %Membrane.File.Sink{location: @output_file}
      },
      links: [
        link(:source) |> via_out(:audio) |> via_in(Pad.ref(:audio, 0)) |> to(:muxer),
        link(:source)
        |> via_out(:video)
        |> to(:video_payloader)
        |> via_in(Pad.ref(:video, 0))
        |> to(:muxer),
        link(:muxer) |> to(:sink)
      ]
    }

    {{:ok, spec: spec, playback: :playing}, %{parent: parent}}
  end

  # Once the source initializes, we grant it the control over the tcp socket
  @impl true
  def handle_notification(
        {:socket_control_needed, _socket, _source} = notification,
        :source,
        _ctx,
        state
      ) do
    send(self(), notification)

    {:ok, state}
  end

  def handle_notification(_notification, _child, _ctx, state) do
    {:ok, state}
  end

  @impl true
  def handle_other({:socket_control_needed, socket, source} = notification, _ctx, state) do
    case Membrane.RTMP.SourceBin.pass_control(socket, source) do
      :ok ->
        :ok

      {:error, :not_owner} ->
        Process.send_after(self(), notification, 200)
    end

    {:ok, state}
  end

  # The rest of the module is used for self-termination of the pipeline after processing finishes
  @impl true
  def handle_element_end_of_stream({:sink, _pad}, _ctx, state) do
    Membrane.Pipeline.terminate(self())
    send(state.parent, :pipeline_terminated)
    {{:ok, playback: :stopped}, state}
  end

  @impl true
  def handle_element_end_of_stream(child, _ctx, state) do
    {:ok, state}
  end
end

defmodule Example do
  @server_ip {127, 0, 0, 1}
  @server_port 5000

  def run() do
    parent = self()

    server_options = %Membrane.RTMP.Source.TcpServer{
      port: @server_port,
      listen_options: [
        :binary,
        packet: :raw,
        active: false,
        ip: @server_ip
      ],
      socket_handler: fn socket ->
        # On new connection a pipeline is started
        Pipeline.start_link(socket: socket, parent: parent)
      end
    }

    Membrane.RTMP.Source.TcpServer.start_link(server_options)

    receive do
      :pipeline_terminated ->
        :ok
    end
  end
end

Example.run()
