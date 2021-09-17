alias Membrane.RTMP.Native

defmodule Functions do
  def recv(callback) do
    callback.()
    receive do
      {:data, data} ->
        File.write!("output.flv", data, [:binary, :append])
        recv(callback)
      after 100 ->
        IO.puts("Let's get more data")
        recv(callback)
    end
  end

  def callback(native) do
    IO.puts("Callback")
    Native.get_frame(native)
    IO.puts("Callback done")
  end
end

{:ok, native} = Native.create("rtmp://127.0.0.1:9009")
IO.puts("Created native")
Functions.recv(fn () -> Functions.callback(native) end)
