defmodule Membrane.RTMP.Source.Test do
  use ExUnit.Case
  import Membrane.Testing.Assertions

  require Logger

  alias Membrane.Testing
  alias Membrane.Testing.Pipeline

  @input_file "test/fixtures/testsrc.flv"
  @port 1935
  @rtmp_stream_url "rtmp://127.0.0.1:#{@port}/"

  test "Check if the stream started and that it ends" do
    assert {:ok, pipeline} = get_testing_pipeline()
    assert_pipeline_playback_changed(pipeline, :prepared, :playing)

    ffmpeg_task = Task.async(&start_ffmpeg/0)

    assert_sink_buffer(pipeline, :audio_sink, %Membrane.Buffer{})
    assert_sink_buffer(pipeline, :video_sink, %Membrane.Buffer{})
    assert_end_of_stream(pipeline, :audio_sink, :input, 11_000)
    assert_end_of_stream(pipeline, :video_sink, :input)

    # Cleanup
    Pipeline.terminate(pipeline, blocking?: true)
    assert :ok = Task.await(ffmpeg_task)
  end

  defp get_testing_pipeline() do
    import Membrane.ParentSpec
    timeout = Membrane.Time.seconds(10)

    options = [
      children: [
        src: %Membrane.RTMP.Source{port: @port, timeout: timeout},
        audio_sink: Testing.Sink,
        video_sink: Testing.Sink
      ],
      links: [
        link(:src) |> via_out(:audio) |> to(:audio_sink),
        link(:src) |> via_out(:video) |> to(:video_sink)
      ],
      test_process: self()
    ]

    Pipeline.start_link(options)
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
