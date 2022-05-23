defmodule Membrane.RTMP.Source.Test do
  use ExUnit.Case
  import Membrane.Testing.Assertions

  alias Membrane.Testing
  alias Membrane.Testing.{Pipeline}

  require Logger

  @input_file "test/fixtures/testsrc.flv"
  @port 9009
  @output_path "rtmp://localhost:#{@port}"

  setup do
    pipeline_pid = get_testing_pipeline() |> start_supervised!()
    Membrane.Testing.Pipeline.play(pipeline_pid)

    %{
      pid: pipeline_pid,
      ffmpeg:
        start_supervised!(%{
          id: :ffmpeg,
          start: {__MODULE__, :start_ffmpeg, []}
        })
    }
  end

  test "Check if the stream started and that it ends", %{pid: pid} do
    assert_pipeline_playback_changed(pid, :prepared, :playing, 10_000)
    assert_sink_buffer(pid, :video_sink, %Membrane.Buffer{})
    assert_sink_buffer(pid, :audio_sink, %Membrane.Buffer{})
    assert_end_of_stream(pid, :audio_sink, :input, 11_000)
    assert_end_of_stream(pid, :video_sink, :input)

    # Cleanup
    Membrane.Testing.Pipeline.terminate(pid, blocking?: true)
    stop_supervised(:ffmpeg)
  end

  defp get_testing_pipeline() do
    import Membrane.ParentSpec

    options = %Membrane.Testing.Pipeline.Options{
      elements: [
        src: %Membrane.RTMP.SourceBin{port: @port},
        audio_sink: Testing.Sink,
        video_sink: Testing.Sink
      ],
      links: [
        link(:src) |> via_out(:audio) |> to(:audio_sink),
        link(:src) |> via_out(:video) |> to(:video_sink)
      ],
      test_process: self()
    }

    %{
      id: :test_pipeline,
      start: {Pipeline, :start_link, [options]}
    }
  end

  @spec start_ffmpeg() :: {:ok, pid()}
  def start_ffmpeg() do
    spawn_link(&execute_loop/0)
    |> then(&{:ok, &1})
  end

  defp execute_loop() do
    import FFmpex
    use FFmpex.Options
    Logger.debug("Starting ffmpeg")

    command =
      FFmpex.new_command()
      |> add_global_option(option_y())
      |> add_input_file(@input_file)
      |> add_file_option(option_re())
      |> add_output_file(@output_path)
      |> add_file_option(option_f("flv"))
      |> add_file_option(option_vcodec("copy"))
      |> add_file_option(option_acodec("copy"))

    case FFmpex.execute(command) do
      :ok ->
        :ok

      error ->
        Logger.error(inspect(error))
        execute_loop()
    end
  end
end
