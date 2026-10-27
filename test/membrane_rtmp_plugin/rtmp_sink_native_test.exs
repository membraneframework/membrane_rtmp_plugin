defmodule Membrane.RTMP.Sink.NativeTest do
  use ExUnit.Case, async: true

  alias Membrane.RTMP.Sink.Native

  test "writing a frame before the stream is ready returns an error" do
    assert {:ok, native} = Native.create("rtmp://localhost:1/app/key", true, true)
    assert {:ok, false, native} = Native.init_video_stream(native, 640, 480, <<>>)

    assert {:error, _reason} = Native.write_video_frame(native, <<0, 0, 0, 1>>, 0, 0, true)
    assert {:error, _reason} = Native.write_audio_frame(native, <<0>>, 0)
  end
end
