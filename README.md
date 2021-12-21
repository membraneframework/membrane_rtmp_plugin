# Membrane RTMP Plugin

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtmp_plugin.svg)](https://hex.pm/packages/membrane_rtmp_plugin)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtmp_plugin)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_rtmp_plugin.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_rtmp_plugin)

This package provides RTMP server which listens to a connection from a client and streaming RTMP client which streams to a server.
### Server
After establishing connection it receives RTMP stream, demux it and outputs H264 video and AAC audio.
At this moment only one client can connect to the server.
### Client
After establishing connection with server it waits to receive H264 video and AAc audio streams. Once both streams are received they are muxed to FLV format and streamed to the server.

It is part of [Membrane Multimedia Framework](https://membraneframework.org).

## Installation

The package can be installed by adding `membrane_rtmp_plugin` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:membrane_rtmp_plugin, "~> 0.2.1"}
  ]
end
```

### Prerequisites
In order to successfully build and install the plugin, you need to have **ffmpeg >= 4.4** installed on your system

## Usage
### Server
Example Server pipeline can look like this:

```elixir
defmodule Example.Server do
  use Membrane.Pipeline

  @port 5_000

  @impl true
  def handle_init(_opts) do
    directory = "hls_output"
    File.rm_rf(directory)
    File.mkdir_p!(directory)

    spec = %ParentSpec{
      children: %{
        :rtmp_server => %Membrane.RTMP.Bin{port: @port},
        :hls => %Membrane.HTTPAdaptiveStream.SinkBin{
          manifest_module: Membrane.HTTPAdaptiveStream.HLS,
          target_window_duration: 20 |> Membrane.Time.seconds(),
          muxer_segment_duration: 2 |> Membrane.Time.seconds(),
          persist?: false,
          storage: %Membrane.HTTPAdaptiveStream.Storages.FileStorage{directory: directory}
        }
      },
      links: [
        link(:rtmp_server)
        |> via_out(:audio)
        |> via_in(Pad.ref(:input, :audio), options: [encoding: :AAC])
        |> to(:hls),
        link(:rtmp_server)
        |> via_out(:video)
        |> via_in(Pad.ref(:input, :video), options: [encoding: :H264])
        |> to(:hls)
      ]
    }

    {{:ok, spec: spec}, %{}}
  end
end
```

It will listen to a connection from a client and convert RTMP stream into HLS playlist.

Run it with:

```elixir
{:ok, pid} = Example.Server.start_link()
Example.Server.play(pid)
```

After this run ffmpeg which will connect to the running server:

```bash
ffmpeg -re -i testsrc.flv -f flv -c:v copy -c:a copy rtmp://localhost:5000
```

`testsrc.flv` can be downloaded from our [tests](test/fixtures/testsrc.flv).

To run this example you will need following extra dependency

```elixir
{:membrane_http_adaptive_stream_plugin, github: "membraneframework/membrane_http_adaptive_stream_plugin"}
```
### Client
Example Streaming Client pipeline might look like this:
```elixir
defmodule Example.Stream do
  use Membrane.Pipeline

  @impl true
  def handle_init(options) do
    children = [
      video_source: %Membrane.File.Source{location: options[:video_file_path]},
      video_parser: %Membrane.H264.FFmpeg.Parser{
        framerate: {25, 1},
        alignment: :au,
        attach_nalus?: true,
        skip_until_keyframe?: true
      },
      audio_parser: %Membrane.AAC.Parser{
        out_encapsulation: :none
      },
      audio_source: %Membrane.File.Source{location: options[:audio_file_path]},
      video_realtimer: Membrane.Realtimer,
      audio_realtimer: Membrane.Realtimer,
      video_payloader: Membrane.MP4.Payloader.H264,
      rtmps_sink: %Membrane.RTMP.Sink{rtmp_url: options[:rtmp_url]}
    ]

    links = [
      link(:video_source)
      |> to(:video_parser)
      |> to(:video_realtimer)
      |> to(:video_payloader)
      |> via_in(:video)
      |> to(:rtmps_sink),
      link(:audio_source)
      |> to(:audio_parser)
      |> to(:audio_realtimer)
      |> via_in(:audio)
      |> to(:rtmps_sink)
    ]

    {{:ok, spec: %ParentSpec{children: children, links: links}}, %{}}
  end

  @impl true
  def handle_element_end_of_stream({:rtmps_sink, pad}, _ctx, %{finished_streams: [closed_pad]} = state) do
    Membrane.Pipeline.stop_and_terminate(self())
    {:ok, Map.put(state, :finished_streams, [pad, closed_pad])}
  end

  @impl true
  def handle_element_end_of_stream({:rtmps_sink, pad}, _ctx, state) do
    {:ok, Map.put(state, :finished_streams, [pad])}
  end

  @impl true
  def handle_element_end_of_stream(_element, _ctx, state) do
    {:ok, state}
  end
end
```
It will connect to RTMP server provided via URL and stream H264 video and AAC audio muxed to FLV format.
RTMP server that will receive this stream can be launched with ffmpeg by running the following commands:
```bash
export RTMP_URL=rtmp://localhost:1935
ffmpeg -listen 1 -f flv -i rtmp://localhost:1935 -c copy dest.flv
```
It will receive stream and once streaming is completed dump it to .flv file.
Run it with:
```elixir
pipeline_options = %{
  video_file_path: "bun33s_480x270.h264",
  audio_file_path: "bun33s.aac",
  rtmp_url: System.get_env("RTMP_URL")
}
{:ok, pid} = Example.Stream.start_link(pipeline_options)
Example.Server.play(pid)
```
[Audio](test/fixtures/bun33.aac) and [Video](test/fixtures/bun33s_480x270.h264) files are present in our tests directory.
Running this example requires the following extra dependencies:
```elixir
{:membrane_realtimer_plugin, "~> 0.4.0"},
{:membrane_file_plugin, "~> 0.6"},
```
## Copyright and License

Copyright 2021, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_rtmp_plugin)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_rtmp_plugin)

Licensed under the [Apache License, Version 2.0](LICENSE)
