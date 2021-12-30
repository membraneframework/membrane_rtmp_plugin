defmodule Membrane.RTMP.Sink.Test do
  use ExUnit.Case, async: true
  import Membrane.Testing.Assertions

  alias Membrane.Testing
  alias Membrane.Testing.{Pipeline}

  require Logger

  @input_video_path "https://raw.githubusercontent.com/membraneframework/static/gh-pages/samples/big-buck-bunny/bun33s_480x270.h264"
  @input_audio_path "https://raw.githubusercontent.com/membraneframework/static/gh-pages/samples/big-buck-bunny/bun33s.aac"

  @rtmp_server_url "rtmp://localhost:49500"
  @reference_flv_path "test/fixtures/bun33s.flv"
  @test_flv_path "/tmp/rtmp_sink_test.flv"

  setup do
    rtmp_server_pid =
      start_supervised!(%{
        id: :rtmp_server,
        start: {__MODULE__, :start_rtmp_server, []}
      })

    %{rtmp_server: rtmp_server_pid}
  end

  test "Check if audio and video streams are correctly received by RTMP server instance" do
    on_exit(fn -> File.rm(@test_flv_path) end)

    sink_pipeline_pid = get_sink_pipeline(@rtmp_server_url) |> start_supervised!()
    Membrane.Testing.Pipeline.play(sink_pipeline_pid)

    assert_pipeline_playback_changed(sink_pipeline_pid, :prepared, :playing)

    assert_start_of_stream(sink_pipeline_pid, :rtmps_sink, :video, 5_000)
    assert_start_of_stream(sink_pipeline_pid, :rtmps_sink, :audio, 5_000)

    assert_end_of_stream(sink_pipeline_pid, :rtmps_sink, :video, 5_000)
    assert_end_of_stream(sink_pipeline_pid, :rtmps_sink, :audio, 5_000)

    Membrane.Testing.Pipeline.stop_and_terminate(sink_pipeline_pid, blocking?: true)
    assert File.exists?(@test_flv_path)
    assert File.stat!(@test_flv_path).size == File.stat!(@reference_flv_path).size
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
        audio_parser: %Membrane.AAC.Parser{
          out_encapsulation: :none
        },
        video_source: %Membrane.Hackney.Source{
          location: @input_video_path,
          hackney_opts: [follow_redirect: true]
        },
        audio_source: %Membrane.Hackney.Source{
          location: @input_audio_path,
          hackney_opts: [follow_redirect: true]
        },
        video_payloader: Membrane.MP4.Payloader.H264,
        rtmps_sink: %Membrane.RTMP.Sink{rtmp_url: rtmp_url}
      ],
      links: [
        link(:video_source)
        |> to(:video_parser)
        |> to(:video_payloader)
        |> via_in(:video)
        |> to(:rtmps_sink),
        link(:audio_source) |> to(:audio_parser) |> via_in(:audio) |> to(:rtmps_sink)
      ],
      test_process: self()
    }

    %{
      id: :sink_pipeline,
      start: {Pipeline, :start_link, [options]}
    }
  end

  @spec start_rtmp_server() :: {:ok, pid()}
  def start_rtmp_server() do
    spawn_link(&execute_loop/0) |> then(&{:ok, &1})
  end

  defp execute_loop() do
    import FFmpex
    use FFmpex.Options

    command =
      FFmpex.new_command()
      |> add_global_option(%FFmpex.Option{
        name: "-listen",
        argument: "1",
        require_arg: true,
        contexts: [:global]
      })
      |> add_input_file(@rtmp_server_url)
      |> add_file_option(option_f("flv"))
      |> add_output_file(@test_flv_path)
      |> add_file_option(option_c("copy"))

    case FFmpex.execute(command) do
      {:ok, _stdout} ->
        :ok

      error ->
        Logger.error(inspect(error))
        execute_loop()
    end
  end
end
