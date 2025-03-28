# Membrane RTMP Plugin

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtmp_plugin.svg)](https://hex.pm/packages/membrane_rtmp_plugin)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtmp_plugin)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_rtmp_plugin.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_rtmp_plugin)

This package provides RTMP server which receives an RTMP stream from a client and an element for streaming to an RTMP server.
It is a part of [Membrane Multimedia Framework](https://membraneframework.org).

## Installation

The package can be installed by adding `membrane_rtmp_plugin` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
	  {:membrane_rtmp_plugin, "~> 0.28.1"}
  ]
end
```

The precompiled builds of the [ffmpeg](https://www.ffmpeg.org) will be pulled and linked automatically. However, should there be any problems, consider installing it manually.

### Manual instalation of dependencies

#### macOS

```shell
brew install ffmpeg
```

#### Ubuntu

```shell
sudo apt-get install ffmpeg
```

#### Arch / Manjaro

```shell
pacman -S ffmpeg
```

## RTMP Server
An simple RTMP server that accepts clients connecting on a given port and allows to distinguish between them
based on app ID and stream key. Each client that has connected is asigned a dedicated client handler, which
behaviour can be provided by RTMP server user.

## SourceBin

Requires a client reference, which identifies a client handler that has been connected to the client, or an URL on which the client is supposed to connect. It receives RTMP stream, demuxes it and outputs H264 video and AAC audio.

## Client

After establishing connection with server it waits to receive video and audio streams. Once both streams are received they are streamed to the server.
Currently only the following codecs are supported:

- H264 for video
- AAC for audio

### Prerequisites

In order to successfully build and install the plugin, you need to have **ffmpeg == 4.4** installed on your system

## Usage

### RTMP receiver

Server-side example, in which Membrane element will act as an RTMP server and receive the stream, can be found under [`examples/source.exs`](examples/source.exs). Please note that
this script allows only for a single client connecting to the RTMP server.
Run it with:

```bash
mix run examples/source.exs
```

When the server is ready you can connect to it with RTMP. If you just want to test it, you can use FFmpeg:

```bash
ffmpeg -re -i test/fixtures/testsrc.flv -f flv -c:v copy -c:a copy rtmp://localhost:1935/app/stream_key
```
When the script terminates, the `testsrc` content should be available in the `received.flv` file.

### RTMP receive with standalone RTMP server

If you want to see how you could setup the `Membrane.RTMPServer` on your own and use it
with cooperation with the `Membane.RTMP.SourceBin`, take a look at [`examples/source_with_standalone_server.exs`](examples/source_with_standalone_server.exs)
Run it with:

```bash
mix run examples/source.exs
```

When the server is ready you can connect to it with RTMP. If you just want to test it, you can use FFmpeg:

```bash
ffmpeg -re -i test/fixtures/testsrc.flv -f flv -c:v copy -c:a copy rtmp://localhost:1935/app/stream_key
```
When the script terminates, the `testsrc` content should be available in the `received.flv` file.

### Streaming with RTMP

Streaming implementation example is provided with the following [`examples/sink.exs`](examples/sink.exs). Run it with:

```bash
elixir examples/sink.exs
```

If you are interested in streaming only a single track. e.g. video, use [`examples/sink_video.exs`](examples/sink_video.exs) instead:

```bash
elixir examples/sink_video.exs
```

It will connect to RTMP server provided via URL and stream H264 video and AAC audio.
RTMP server that will receive this stream can be launched with ffmpeg by running the following commands:

```bash
ffmpeg -y -listen 1 -f flv -i rtmp://localhost:1935 -c copy dest.flv
```

It will receive stream and once streaming is completed dump it to .flv file. If you are using the command above, please remember to run it **before** the streaming script.

## Copyright and License

Copyright 2021, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_rtmp_plugin)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_rtmp_plugin)

Licensed under the [Apache License, Version 2.0](LICENSE)
