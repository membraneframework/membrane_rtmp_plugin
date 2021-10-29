# Membrane RTMP Plugin

[![Hex.pm](https://img.shields.io/hexpm/v/membrane_rtmp_plugin.svg)](https://hex.pm/packages/membrane_rtmp_plugin)
[![API Docs](https://img.shields.io/badge/api-docs-yellow.svg?style=flat)](https://hexdocs.pm/membrane_rtmp_plugin)
[![CircleCI](https://circleci.com/gh/membraneframework/membrane_rtmp_plugin.svg?style=svg)](https://circleci.com/gh/membraneframework/membrane_rtmp_plugin)

This package provides RTMP server which listens to a connection from a client.
After establishing connection it receives RTMP stream, demux it and outputs H264 video and AAC audio.
At this moment only one client can connect to the server.

It is part of [Membrane Multimedia Framework](https://membraneframework.org).

## Installation

The package can be installed by adding `membrane_rtmp_plugin` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:membrane_rtmp_plugin, "~> 0.1.0"}
  ]
end
```

## Usage
Example Server pipeline can look like this:
```elixir
defmodule Example.Server do
  use Membrane.Pipeline

  @port 5_000

  @impl true
  def handle_init(_opts) do
    spec = %ParentSpec{
      children: %{
        :rtmp_server => %Membrane.RTMP.Bin{port: @port},
        :audio_file => %Membrane.File.Sink{location: "./audio.aac"},
        :video_file => %Membrane.File.Sink{location: "./video.h264"}
      },
      links: [
        link(:rtmp_server) |> via_out(:audio) |> to(:audio_file),
        link(:rtmp_server) |> via_out(:video) |> to(:video_file)
      ]
    }
    {{:ok, spec: spec}, %{}}
  end
end
```

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

## Copyright and License

Copyright 2021, [Software Mansion](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_rtmp_plugin)

[![Software Mansion](https://logo.swmansion.com/logo?color=white&variant=desktop&width=200&tag=membrane-github)](https://swmansion.com/?utm_source=git&utm_medium=readme&utm_campaign=membrane_rtmp_plugin)

Licensed under the [Apache License, Version 2.0](LICENSE)
