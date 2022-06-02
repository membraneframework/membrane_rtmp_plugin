defmodule Membrane.RTMP.Source.Native do
  @moduledoc false
  use Unifex.Loader

  alias Membrane.Time

  @spec await_connection(reference(), String.t(), Time.t()) ::
          {:ok, reference()} | {:error, reason :: any()}
  def await_connection(native, url, timeout) do
    timeout = get_int_timeout(timeout)
    creator = self()

    spawn(fn ->
      ref = Process.monitor(creator)

      receive do
        {:DOWN, ^ref, :process, ^creator, _reason} -> set_terminate(native)
      end
    end)

    await_open(native, url, timeout)
  end

  @one_second Time.second()

  defp get_int_timeout(:infinity), do: 0

  defp get_int_timeout(time) when rem(time, @one_second) != 0 do
    raise ArgumentError,
          "Timeout must be a multiply of one second. #{Time.pretty_duration(time)} is not"
  end

  defp get_int_timeout(time) do
    Time.as_seconds(time) |> Ratio.trunc()
  end
end
