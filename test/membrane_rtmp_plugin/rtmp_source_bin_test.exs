defmodule Membrane.RTMP.SourceBin.Test do
  use ExUnit.Case

  import Membrane.Testing.Assertions

  require Logger

  alias Membrane.RTMP.Source.TcpServer
  alias Membrane.Testing

  @input_file "test/fixtures/testsrc.flv"
  @port 9009
  @local_ip "127.0.0.1"
  @rtmp_stream_url "rtmp://#{@local_ip}:#{@port}/"

  test "Check if the stream started and that it ends" do
    test_process = self()

    options = %TcpServer{
      port: @port,
      listen_options: [
        :binary,
        packet: :raw,
        active: false,
        ip: @local_ip |> String.to_charlist() |> :inet.parse_address() |> elem(1)
      ],
      socket_handler: fn socket ->
        options = [
          module: Membrane.RTMP.Source.TestPipeline,
          custom_args: [socket: socket, test_process: test_process],
          test_process: test_process
        ]

        Testing.Pipeline.start_link(options)
      end
    }

    {:ok, _tcp_server} = TcpServer.start_link(options)
    ffmpeg_task = Task.async(&start_ffmpeg/0)

    pipeline = await_pipeline_started()

    assert_pipeline_playback_changed(pipeline, :prepared, :playing)

    assert_sink_buffer(pipeline, :video_sink, %Membrane.Buffer{})
    assert_sink_buffer(pipeline, :audio_sink, %Membrane.Buffer{})
    assert_end_of_stream(pipeline, :audio_sink, :input, 11_000)
    assert_end_of_stream(pipeline, :video_sink, :input)

    # Cleanup
    Testing.Pipeline.terminate(pipeline, blocking?: true)
    assert :ok = Task.await(ffmpeg_task)
  end

  defp start_ffmpeg() do
    import FFmpex
    use FFmpex.Options
    Logger.debug("Starting ffmpeg")

    command =
      FFmpex.new_command()
      |> add_global_option(option_y())
      |> add_input_file(@input_file)
      |> add_file_option(option_re())
      |> add_output_file(@rtmp_stream_url)
      |> add_file_option(option_f("flv"))
      |> add_file_option(option_vcodec("copy"))
      |> add_file_option(option_acodec("copy"))

    case FFmpex.execute(command) do
      {:ok, ""} ->
        :ok

      error ->
        Logger.error(inspect(error))
        :error
    end
  end

  defp await_pipeline_started() do
    receive do
      {:pipeline_started, pid} -> pid
    end
  end
end
