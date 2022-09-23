defmodule Membrane.RTMP.SourceBin.IntegrationTest do
  use ExUnit.Case, async: true

  import Membrane.Testing.Assertions

  require Logger

  alias Membrane.RTMP.Source.TcpServer
  alias Membrane.Testing

  @input_file "test/fixtures/testsrc.flv"
  @local_ip "127.0.0.1"
  @stream_key "ala2137"

  @stream_length_ms 3000
  @video_frame_duration_ms 42
  @audio_frame_duration_ms 23

  test "SourceBin outputs the correct number of audio and video buffers" do
    {:ok, port} = start_tcp_server()

    ffmpeg_task =
      Task.async(fn ->
        get_stream_url(port) |> start_ffmpeg()
      end)

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

  test "Correct Stream ID is correctly verified" do
    {:ok, port} = start_tcp_server(Membrane.RTMP.Source.TestVerifier)

    ffmpeg_task =
      Task.async(fn ->
        get_stream_url(port, @stream_key) |> start_ffmpeg()
      end)

    pipeline = await_pipeline_started()
    assert_pipeline_playback_changed(pipeline, :prepared, :playing)

    assert_end_of_stream(pipeline, :audio_sink, :input, @stream_length_ms + 500)
    assert_end_of_stream(pipeline, :video_sink, :input)

    # Cleanup
    Testing.Pipeline.terminate(pipeline, blocking?: true)
    assert :ok = Task.await(ffmpeg_task)
  end

  test "Wrong Stream ID is denied" do
    {:ok, port} = start_tcp_server(Membrane.RTMP.Source.TestVerifier)

    ffmpeg_task =
      Task.async(fn ->
        get_stream_url(port, @stream_key <> "wrong") |> start_ffmpeg()
      end)

    pipeline = await_pipeline_started()
    assert_pipeline_playback_changed(pipeline, :prepared, :playing)

    assert_pipeline_notified(
      pipeline,
      :src,
      {:stream_validation_failed, "wrong stream key"}
    )

    # Cleanup
    Testing.Pipeline.terminate(pipeline, blocking?: true)
    assert :error = Task.await(ffmpeg_task)
  end

  defp start_tcp_server(verifier \\ Membrane.RTMP.DefaultValidator) do
    test_process = self()

    options = %TcpServer{
      port: 0,
      listen_options: [
        :binary,
        packet: :raw,
        active: false,
        ip: @local_ip |> String.to_charlist() |> :inet.parse_address() |> elem(1)
      ],
      socket_handler: fn socket ->
        options = [
          module: Membrane.RTMP.Source.TestPipeline,
          custom_args: [socket: socket, test_process: test_process, verifier: verifier],
          test_process: test_process
        ]

        Testing.Pipeline.start_link(options)
      end,
      parent: test_process
    }

    {:ok, _tcp_server} = TcpServer.start_link(options)

    receive do
      {:tcp_server_started, socket} ->
        :inet.port(socket)
    end
  end

  defp get_stream_url(port, key \\ nil) do
    "rtmp://#{@local_ip}:#{port}" <>
      if key, do: "/app/" <> key, else: ""
  end

  defp start_ffmpeg(stream_url) do
    import FFmpex
    use FFmpex.Options
    Logger.debug("Starting ffmpeg")

    command =
      FFmpex.new_command()
      |> add_global_option(option_y())
      |> add_input_file(@input_file)
      |> add_file_option(option_re())
      |> add_output_file(stream_url)
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
