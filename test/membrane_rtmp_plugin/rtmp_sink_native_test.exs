defmodule Membrane.RTMP.Sink.NativeTest do
  use ExUnit.Case, async: true

  alias Membrane.RTMP.Sink.Native

  test "writing a frame before the stream is ready returns an error" do
    assert {:ok, native} = Native.create("rtmp://localhost:1/app/key", true, true)
    assert {:ok, false, native} = Native.init_video_stream(native, 640, 480, 0, <<>>)

    assert {:error, :not_ready} = Native.write_video_frame(native, <<0, 0, 0, 1>>, 0, 0, true)
    assert {:error, :not_initialized} = Native.write_audio_frame(native, <<0>>, 0)
  end

  test "initializing the last stream before connecting returns an error" do
    assert {:ok, native} = Native.create("rtmp://localhost:1/app/key", false, true)

    assert {:error, :not_connected} = Native.init_video_stream(native, 640, 480, 0, <<>>)
  end

  test "using the stream after it is closed returns an error" do
    assert {:ok, native} = Native.create("rtmp://localhost:1/app/key", true, true)
    assert {:ok, false, native} = Native.init_video_stream(native, 640, 480, 0, <<>>)
    assert :ok = Native.finalize_stream(native)

    assert {:error, :closed} = Native.try_connect(native)
    assert {:error, :closed} = Native.write_video_frame(native, <<0>>, 0, 0, true)
    assert {:error, :closed} = Native.init_audio_stream(native, 2, 44_100, 0, <<>>)
  end
end
