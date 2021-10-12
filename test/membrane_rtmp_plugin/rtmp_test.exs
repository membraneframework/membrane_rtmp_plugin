defmodule Membrane.RTMP.Source.Test do
  use ExUnit.Case
  use Bunch

  import Membrane.Testing.Assertions
  alias Membrane.Testing
  alias Membrane.Testing.{Pipeline}

  @input_file "test/fixtures/testsrc.flv"
  @port 9009
  @output_path "rtmp://localhost:#{@port}"

  test "Check if the stream started and that it ends" do
    spawn(&start_ffmpeg/0)
    {:ok, pid} = get_testing_pipeline()
    start_ffmpeg()
    assert_pipeline_playback_changed(pid, :prepared, :playing)
    assert_sink_buffer(pid, :video_sink, %Membrane.Buffer{})
    refute_sink_buffer(pid, :audio_sink, %Membrane.Buffer{})
  end

  defp get_testing_pipeline() do
    import Membrane.ParentSpec

    options = %Membrane.Testing.Pipeline.Options{
      elements: [
        src: %Membrane.RTMP.Source{port: @port},
        audio_sink: Testing.Sink,
        video_sink: Testing.Sink
      ],
      links: [
        link(:src) |> via_out(:audio) |> to(:audio_sink),
        link(:src) |> via_out(:video) |> to(:video_sink)
      ]
    }

    {:ok, pid} = Pipeline.start_link(options)
    :ok = Pipeline.play(pid)
    {:ok, pid}
  end

  defp start_ffmpeg() do
    Process.sleep(200)
    System.shell("ffmpeg -re -i #{@input_file} -f flv -c:v copy #{@output_path}", cd: File.cwd!())
  end
end
