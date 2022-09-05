defmodule Membrane.RTMP.Source.Test do
  use ExUnit.Case
  import Membrane.Testing.Assertions

  require Logger

  alias Membrane.Testing

  @input_file "test/fixtures/testsrc.flv"
  @port 9009
  @local_ip "127.0.0.1"
  @rtmp_stream_url "rtmp://#{@local_ip}:#{@port}/"

  test "Check if the stream started and that it ends" do
    Process.register(self(), __MODULE__)
    Task.start_link(&get_testing_pipeline/0)

    Process.sleep(500)
    pipeline = Process.whereis(Membrane.RTMP.Source.Test.Pipeline)

    assert_pipeline_playback_changed(pipeline, :prepared, :playing)

    ffmpeg_task = Task.async(&start_ffmpeg/0)

    assert_sink_buffer(pipeline, :video_sink, %Membrane.Buffer{})
    assert_sink_buffer(pipeline, :audio_sink, %Membrane.Buffer{})
    assert_end_of_stream(pipeline, :audio_sink, :input, 11_000)
    assert_end_of_stream(pipeline, :video_sink, :input)

    # Cleanup
    Testing.Pipeline.terminate(pipeline, blocking?: true)
    assert :ok = Task.await(ffmpeg_task)
  end

  defp get_testing_pipeline() do
    import Membrane.ParentSpec
    timeout = Membrane.Time.seconds(10)

    options = [
      module: Membrane.RTMP.Source.Test.Pipeline,
      custom_args: [local_ip: @local_ip, port: @port, timeout: timeout],
      test_process: Process.whereis(__MODULE__)
    ]

    {:ok, pid} = Testing.Pipeline.start_link(options)
    :ok = Membrane.Pipeline.play(pid)
    {:ok, pid}
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
end
