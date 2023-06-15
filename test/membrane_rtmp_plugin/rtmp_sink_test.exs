defmodule Membrane.RTMP.SinkTest do
  use ExUnit.Case, async: true
  import Membrane.Testing.Assertions

  require Logger

  require Membrane.Pad

  alias Membrane.Pad
  alias Membrane.Testing.Pipeline

  @input_video_url "https://raw.githubusercontent.com/membraneframework/static/gh-pages/samples/big-buck-bunny/bun33s_480x270.h264"
  @input_audio_url "https://raw.githubusercontent.com/membraneframework/static/gh-pages/samples/big-buck-bunny/bun33s.aac"

  @rtmp_server_url "rtmp://localhost:49500/app/sink_test"
  @reference_flv_path "test/fixtures/bun33s.flv"
  @reference_flv_audio_path "test/fixtures/bun33s_audio.flv"
  @reference_flv_video_path "test/fixtures/bun33s_video.flv"

  setup ctx do
    flv_output_file = Path.join(ctx.tmp_dir, "rtmp_sink_test.flv")
    %{flv_output_file: flv_output_file}
  end

  @tag :tmp_dir
  test "Checks if audio and video are interleaved correctly", %{tmp_dir: tmp_dir} do
    output_file = Path.join(tmp_dir, "rtmp_sink_interleave_test.flv")

    rtmp_server = Task.async(fn -> start_rtmp_server(output_file) end)
    sink_pipeline_pid = start_interleaving_sink_pipeline(@rtmp_server_url)

    # There's an RC - there's no way to ensure RTMP server starts to listen before pipeline is started
    # so it may retry a few times before succeeding
    assert_pipeline_play(sink_pipeline_pid, 5000)

    assert_start_of_stream(sink_pipeline_pid, :rtmp_sink, Pad.ref(:video, 0), 5_000)
    assert_start_of_stream(sink_pipeline_pid, :rtmp_sink, Pad.ref(:audio, 0))

    assert_end_of_stream(sink_pipeline_pid, :rtmp_sink, Pad.ref(:video, 0), 5_000)
    assert_end_of_stream(sink_pipeline_pid, :rtmp_sink, Pad.ref(:audio, 0))

    :ok = Pipeline.terminate(sink_pipeline_pid, blocking?: true)
    # RTMP server should terminate when the connection is closed
    assert :ok = Task.await(rtmp_server)

    assert File.exists?(output_file)
  end

  @tag :tmp_dir
  test "Check if audio and video streams are correctly received by RTMP server instance", %{
    flv_output_file: flv_output_file
  } do
    test_stream_correctly_received(flv_output_file, @reference_flv_path, [:audio, :video])
  end

  @tag :tmp_dir
  test "Check if a single audio track is correctly received by RTMP server instance", %{
    flv_output_file: flv_output_file
  } do
    test_stream_correctly_received(flv_output_file, @reference_flv_audio_path, [:audio])
  end

  @tag :tmp_dir
  test "Check if a single video track is correctly received by RTMP server instance", %{
    flv_output_file: flv_output_file
  } do
    test_stream_correctly_received(flv_output_file, @reference_flv_video_path, [:video])
  end

  defp test_stream_correctly_received(flv_output, fixture, tracks) do
    rtmp_server = Task.async(fn -> start_rtmp_server(flv_output) end)

    sink_pipeline_pid = start_sink_pipeline(@rtmp_server_url, tracks)

    # There's an RC - there's no way to ensure RTMP server starts to listen before pipeline is started
    # so it may retry a few times before succeeding
    assert_pipeline_play(sink_pipeline_pid, 5000)

    Enum.each(
      tracks,
      &assert_start_of_stream(sink_pipeline_pid, :rtmp_sink, Pad.ref(&1, 0), 5_000)
    )

    Enum.each(tracks, &assert_end_of_stream(sink_pipeline_pid, :rtmp_sink, Pad.ref(&1, 0), 5_000))

    :ok = Pipeline.terminate(sink_pipeline_pid, blocking?: true)
    # RTMP server should terminate when the connection is closed
    assert :ok = Task.await(rtmp_server)

    assert File.exists?(flv_output)
    assert File.stat!(flv_output).size == File.stat!(fixture).size
  end

  defp start_interleaving_sink_pipeline(rtmp_url) do
    import Membrane.ChildrenSpec

    options = [
      structure: [
        child(:rtmp_sink, %Membrane.RTMP.Sink{rtmp_url: rtmp_url, max_attempts: 5}),
        #
        child(:video_source, %Membrane.File.Source{location: "test/fixtures/video.msr"})
        |> child(:video_deserializer, Membrane.Stream.Deserializer)
        |> child(:video_parser, %Membrane.H264.FFmpeg.Parser{
          alignment: :au,
          attach_nalus?: true,
          skip_until_parameters?: true
        })
        |> child(:video_payloader, Membrane.MP4.Payloader.H264)
        |> via_in(Pad.ref(:video, 0))
        |> get_child(:rtmp_sink),
        #
        child(:audio_source, %Membrane.File.Source{location: "test/fixtures/audio.msr"})
        |> child(:audio_deserializer, Membrane.Stream.Deserializer)
        |> child(:audio_parser, Membrane.AAC.Parser)
        |> via_in(Pad.ref(:audio, 0))
        |> get_child(:rtmp_sink)
      ],
      test_process: self()
    ]

    Pipeline.start_link_supervised!(options)
  end

  defp start_sink_pipeline(rtmp_url, tracks) do
    import Membrane.ChildrenSpec

    options = [
      structure:
        [
          child(:rtmp_sink, %Membrane.RTMP.Sink{
            rtmp_url: rtmp_url,
            tracks: tracks,
            max_attempts: 5
          })
        ] ++
          get_audio_elements(tracks) ++
          get_video_elements(tracks),
      test_process: self()
    ]

    Pipeline.start_link_supervised!(options)
  end

  defp get_audio_elements(tracks) do
    import Membrane.ChildrenSpec

    if :audio in tracks do
      [
        child(:audio_source, %Membrane.Hackney.Source{
          location: @input_audio_url,
          hackney_opts: [follow_redirect: true]
        })
        |> child(:audio_parser, %Membrane.AAC.Parser{
          out_encapsulation: :none
        })
        |> via_in(Pad.ref(:audio, 0))
        |> get_child(:rtmp_sink)
      ]
    else
      []
    end
  end

  defp get_video_elements(tracks) do
    import Membrane.ChildrenSpec

    if :video in tracks do
      [
        child(:video_source, %Membrane.Hackney.Source{
          location: @input_video_url,
          hackney_opts: [follow_redirect: true]
        })
        |> child(:video_parser, %Membrane.H264.FFmpeg.Parser{
          framerate: {30, 1},
          alignment: :au,
          attach_nalus?: true,
          skip_until_parameters?: false
        })
        |> child(:video_payloader, Membrane.MP4.Payloader.H264)
        |> via_in(Pad.ref(:video, 0))
        |> get_child(:rtmp_sink)
      ]
    else
      []
    end
  end

  @spec start_rtmp_server(Path.t()) :: :ok | :error
  def start_rtmp_server(out_file) do
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
      |> add_output_file(out_file)
      |> add_file_option(option_c("copy"))

    case FFmpex.execute(command) do
      {:ok, _stdout} ->
        :ok

      {:error, {error, exit_code}} ->
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
end
