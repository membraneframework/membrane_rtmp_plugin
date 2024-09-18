defmodule Membrane.RTMP.SourceBin.IntegrationTest do
  use ExUnit.Case, async: true

  import Membrane.Testing.Assertions

  require Logger

  alias Membrane.Testing

  @input_file "test/fixtures/testsrc.flv"
  @app "liveapp"
  @stream_key "ala2137"
  @default_port 22_224

  @stream_length_ms 3000
  @video_frame_duration_ms 42
  @audio_frame_duration_ms 24

  test "SourceBin outputs the correct number of audio and video buffers when the client connects to the given app and stream key" do
    self = self()

    pipeline_startup_task =
      Task.async(fn ->
        start_pipeline_with_external_rtmp_server(@app, @stream_key, self)
      end)

    port =
      receive do
        {:port, port} -> port
      end

    ffmpeg_task =
      Task.async(fn ->
        "rtmp://localhost:#{port}/#{@app}/#{@stream_key}" |> start_ffmpeg()
      end)

    pipeline = Task.await(pipeline_startup_task)

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
    Testing.Pipeline.terminate(pipeline)
    assert :ok = Task.await(ffmpeg_task)
  end

  test "SourceBin doesn't output anything if the client tries to connect to different app or stream key" do
    {port, pipeline} = start_pipeline_with_builtin_rtmp_server(@app, @stream_key)
    other_app = "other_app"
    other_stream_key = "other_stream_key"

    ffmpeg_task =
      Task.async(fn ->
        "rtmp://localhost:#{port}/#{other_app}/#{other_stream_key}" |> start_ffmpeg()
      end)

    refute_sink_buffer(pipeline, :video_sink, _any)
    refute_sink_buffer(pipeline, :audio_sink, _any)

    # Cleanup
    Testing.Pipeline.terminate(pipeline)

    # Error is expected because connection will be refused and thus ffmpeg fails
    ffmpeg_result = Task.await(ffmpeg_task, 10_000)
    assert ffmpeg_result == :error
  end

  @tag :rtmps
  test "SourceBin allows for RTMPS connection" do
    self = self()

    pipeline_startup_task =
      Task.async(fn ->
        start_pipeline_with_external_rtmp_server(@app, @stream_key, self, 0, true)
      end)

    port =
      receive do
        {:port, port} -> port
      end

    ffmpeg_task =
      Task.async(fn ->
        "rtmps://localhost:#{port}/#{@app}/#{@stream_key}" |> start_ffmpeg()
      end)

    pipeline = Task.await(pipeline_startup_task)

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
    Testing.Pipeline.terminate(pipeline)
    assert :ok = Task.await(ffmpeg_task)
  end

  # maximum timestamp in milliseconds
  @extended_timestamp_tag 0xFFFFFF
  test "SourceBin gracefully handles timestamp overflow" do
    # offset half a second in the past
    offset = @extended_timestamp_tag / 1_000 - 0.5

    self = self()

    pipeline_startup_task =
      Task.async(fn ->
        start_pipeline_with_external_rtmp_server(@app, @stream_key, self)
      end)

    port =
      receive do
        {:port, port} -> port
      end

    ffmpeg_task =
      Task.async(fn ->
        "rtmp://localhost:#{port}/#{@app}/#{@stream_key}" |> start_ffmpeg(ts_offset: offset)
      end)

    pipeline = Task.await(pipeline_startup_task)

    assert_buffers(%{
      pipeline: pipeline,
      sink: :audio_sink,
      stream_length: trunc(@stream_length_ms + offset * 1_000),
      buffers_expected: div(@stream_length_ms, @audio_frame_duration_ms)
    })

    assert_end_of_stream(pipeline, :audio_sink, :input, @stream_length_ms + 500)
    assert_end_of_stream(pipeline, :video_sink, :input)

    # Cleanup
    Testing.Pipeline.terminate(pipeline)
    assert :ok = Task.await(ffmpeg_task)
  end

  test "SourceBin gracefully handles start when starting after timestamp overflow" do
    # offset five seconds in the future
    offset = @extended_timestamp_tag / 1_000 + 5

    self = self()

    pipeline_startup_task =
      Task.async(fn ->
        start_pipeline_with_external_rtmp_server(@app, @stream_key, self)
      end)

    port =
      receive do
        {:port, port} -> port
      end

    ffmpeg_task =
      Task.async(fn ->
        "rtmp://localhost:#{port}/#{@app}/#{@stream_key}" |> start_ffmpeg(ts_offset: offset)
      end)

    pipeline = Task.await(pipeline_startup_task)

    assert_buffers(%{
      pipeline: pipeline,
      sink: :audio_sink,
      stream_length: trunc(@stream_length_ms + offset * 1_000),
      buffers_expected: div(@stream_length_ms, @audio_frame_duration_ms)
    })

    assert_end_of_stream(pipeline, :audio_sink, :input, @stream_length_ms)
    assert_end_of_stream(pipeline, :video_sink, :input)

    # Cleanup
    Testing.Pipeline.terminate(pipeline)
    assert :ok = Task.await(ffmpeg_task)
  end

  defp start_pipeline_with_builtin_rtmp_server(app, stream_key, use_ssl? \\ false) do
    options = [
      module: Membrane.RTMP.Source.WithBuiltinServerTestPipeline,
      custom_args: %{app: app, stream_key: stream_key, port: @default_port, use_ssl?: use_ssl?},
      test_process: self()
    ]

    pipeline_pid = Testing.Pipeline.start_link_supervised!(options)
    {@default_port, pipeline_pid}
  end

  defp start_pipeline_with_external_rtmp_server(
         app,
         stream_key,
         parent,
         port \\ 0,
         use_ssl? \\ false
       ) do
    parent_process_pid = self()

    handle_new_client = fn client_ref, app, stream_key ->
      send(parent_process_pid, {:client_ref, client_ref, app, stream_key})
      Membrane.RTMP.Source.ClientHandlerImpl
    end

    {:ok, server_pid} =
      Membrane.RTMPServer.start_link(
        port: port,
        use_ssl?: use_ssl?,
        handle_new_client: handle_new_client,
        client_timeout: 3_000
      )

    {:ok, assigned_port} = Membrane.RTMPServer.get_port(server_pid)

    send(parent, {:port, assigned_port})

    {:ok, client_ref} =
      receive do
        {:client_ref, client_ref, ^app, ^stream_key} ->
          {:ok, client_ref}
      after
        5000 -> :timeout
      end

    options = [
      module: Membrane.RTMP.Source.WithExternalServerTestPipeline,
      custom_args: %{client_ref: client_ref},
      test_process: parent
    ]

    {:ok, _supervisor, pid} = Testing.Pipeline.start_link(options)
    pid
  end

  defp start_ffmpeg(stream_url, opts \\ []) do
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
      |> maybe_add_file_timestamps_offset(opts)

    {command, args} = FFmpex.prepare(command)

    case System.cmd(command, args) do
      {_output, 0} ->
        :ok

      {error, exit_code} ->
        Logger.error(
          """
          FFmpeg exited with a non-zero exit code (#{exit_code}) and the error message:
          #{error}
          """
          |> String.trim()
        )

        :error
    end
  end

  defp maybe_add_file_timestamps_offset(command, options) do
    if ts_offset = Keyword.get(options, :ts_offset) do
      add_file_timestamps_offset(command, ts_offset)
    else
      command
    end
  end

  defp add_file_timestamps_offset(command, offset) do
    FFmpex.add_file_option(command, %FFmpex.Option{
      name: "-output_ts_offset",
      argument: offset,
      contexts: [:output]
    })
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
