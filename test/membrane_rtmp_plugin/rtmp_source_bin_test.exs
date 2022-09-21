defmodule Membrane.RTMP.SourceBin.IntegrationTest do
  use ExUnit.Case

  import Membrane.Testing.Assertions

  require Logger

  alias Membrane.RTMP.Source.TcpServer
  alias Membrane.Testing

  @input_file "test/fixtures/testsrc.flv"
  @port 1935
  @local_ip "127.0.0.1"
  @stream_key "ala2137"
  @rtmp_stream_url "rtmp://#{@local_ip}:#{@port}/app/#{@stream_key}"

  @stream_length_ms 3000
  @video_frame_duration_ms 42
  @audio_frame_duration_ms 23

  test "SourceBin outputs the correct number of audio and video buffers" do
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

    assert_buffers(%{
      pipeline: pipeline,
      sink: :video_sink,
      stream_length: @stream_length_ms,
      buffers_expected: div(@stream_length_ms, @video_frame_duration_ms)
    })

    assert_buffers(%{
      pipeline: pipeline,
      sink: :audio_sink,
      stream_length: @stream_length_ms,
      buffers_expected: div(@stream_length_ms, @audio_frame_duration_ms)
    })

    assert_end_of_stream(pipeline, :audio_sink, :input)
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

  defp assert_buffers(%{last_dts: _dts} = state) do
    assert_sink_buffer(state.pipeline, state.sink, %Membrane.Buffer{dts: dts})
    assert dts >= state.last_dts

    buffers = state.buffers + 1
    state = %{state | last_dts: dts, buffers: buffers}

    if dts < state.stream_length do
      assert_buffers(state)
    else
      assert state.buffers >= state.buffers_expected
    end
  end

  defp assert_buffers(state) do
    stream_length = Membrane.Time.milliseconds(state.stream_length)

    state
    |> Map.merge(%{stream_length: stream_length, last_dts: -1, buffers: 0})
    |> assert_buffers()
  end
end
