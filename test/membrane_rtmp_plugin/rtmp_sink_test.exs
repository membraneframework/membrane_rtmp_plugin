defmodule Membrane.RTMP.Sink.Test do
  use ExUnit.Case, async: true
  import Membrane.Testing.Assertions

  alias Membrane.Testing
  alias Membrane.Testing.{Pipeline}

  @input_video_path "test/fixtures/testvideo.h264"

  @flv_path "/tmp/rtmp_sink_test.flv"

  test "Check if audio and video streams are correctly dumped to .flv file" do
    on_exit(fn -> File.rm(@flv_path) end)
    File.touch!(@flv_path)

    sink_pipeline_pid = get_sink_pipeline(@flv_path) |> start_supervised!()
    Membrane.Testing.Pipeline.play(sink_pipeline_pid)

    assert_pipeline_playback_changed(sink_pipeline_pid, :prepared, :playing)
    assert File.exists?(@flv_path)
    assert_start_of_stream(sink_pipeline_pid, :rtmps_sink, :video, 5_000)
    assert_end_of_stream(sink_pipeline_pid, :rtmps_sink, :video, 5_000)

    Membrane.Testing.Pipeline.stop_and_terminate(sink_pipeline_pid, blocking?: true)
  end

  defp get_sink_pipeline(rtmp_url) do
    import Membrane.ParentSpec

    options = %Membrane.Testing.Pipeline.Options{
      elements: [
        video_parser: %Membrane.H264.FFmpeg.Parser{
          framerate: {30, 1},
          alignment: :au,
          attach_nalus?: true
        },
        video_source: %Membrane.File.Source{location: @input_video_path},
        rtmps_sink: %Membrane.RTMP.Sink{rtmp_url: rtmp_url}
      ],
      links: [
        link(:video_source) |> to(:video_parser) |> via_in(:video) |> to(:rtmps_sink)
      ],
      test_process: self()
    }

    %{
      id: :sink_pipeline,
      start: {Pipeline, :start_link, [options]}
    }
  end
end
