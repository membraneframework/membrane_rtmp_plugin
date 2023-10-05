# Membrane RTMP Plugin

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtmp_plugin.svg)](https://hex.pm/packages/membrane_rtmp_plugin)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtmp_plugin)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_rtmp_plugin.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_rtmp_plugin)

This package provides RTMP server which receives an RTMP stream from a client and an element for streaming to an RTMP server.
It is a part of [Membrane Multimedia Framework](https://membraneframework.org).

## Installation

First, you need to install FFmpeg on your system:

### macOS

```shell
brew install ffmpeg
```

### Ubuntu

```shell
sudo apt-get install ffmpeg
```

The package can be installed by adding `membrane_rtmp_plugin` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
	  {:membrane_rtmp_plugin, "~> 0.17.3"}
  ]
end
```

## SourceBin

Requires a socket, which has been connected to the client. It receives RTMP stream, demuxes it and outputs H264 video and AAC audio.

## Client

After establishing connection with server it waits to receive video and audio streams. Once both streams are received they are streamed to the server.
Currently only the following codecs are supported:

- H264 for video
- AAC for audio

## TCP Server

It's a simple implementation of tcp server. It opens a tcp port and listens for incoming connections. For each new connection, a user-provided function is executed.

### Prerequisites

In order to successfully build and install the plugin, you need to have **ffmpeg == 4.4** installed on your system

## Usage

### RTMP receiver

Server-side example, in which Membrane will act as an RTMP server and receive the stream, can be found under [`examples/source.exs`](examples/source.exs). Run it with:

```bash
elixir examples/source.exs
```

When the server is ready you can connect to it with RTMP. If you just want to test it, you can use FFmpeg:

```bash
ffmpeg -re -i test/fixtures/testsrc.flv -f flv -c:v copy -c:a copy rtmp://localhost:5000
```

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
export RTMP_URL=rtmp://localhost:1935
ffmpeg -y -listen 1 -f flv -i rtmp://localhost:1935 -c copy dest.flv
```

It will receive stream and once streaming is completed dump it to .flv file. If you are using the command above, please remember to run it **before** the streaming script.

## Copyright and License

Copyright 2021, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_rtmp_plugin)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_rtmp_plugin)

Licensed under the [Apache License, Version 2.0](LICENSE)
