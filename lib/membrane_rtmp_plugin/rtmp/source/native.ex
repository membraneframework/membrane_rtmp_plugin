defmodule Membrane.RTMP.Source.Native do
  @moduledoc false
  use Unifex.Loader

  require Logger

  alias Membrane.Time

  @one_second Time.second()

  @spec start_link(url :: String.t(), timeout :: integer()) :: pid()
  def start_link(url, timeout) do
    {:ok, native_ref} = create()
    caller_pid = self()

    spawn(fn ->
      ref = Process.monitor(caller_pid)

      receive do
        {:DOWN, ^ref, :process, ^caller_pid, _reason} -> set_terminate(native_ref)
      end
    end)

    timeout = get_int_timeout(timeout)

    spawn_link(fn ->
      Process.monitor(caller_pid)
      send(self(), {:await_connection, url, timeout})
      receive_loop(native_ref, caller_pid)
    end)
  end

  defp get_int_timeout(:infinity), do: 0

  defp get_int_timeout(time) when rem(time, @one_second) != 0 do
    raise ArgumentError,
          "Timeout must be a multiply of one second. #{Time.pretty_duration(time)} is not"
  end

  defp get_int_timeout(time) do
    time |> Time.as_seconds() |> Ratio.trunc()
  end

  defp receive_loop(native_ref, target) do
    receive do
      {:await_connection, url, timeout} ->
        await_connection(native_ref, target, url, timeout)

      :get_frame ->
        result = read_frame(native_ref)
        send(target, {__MODULE__, :read_frame, result})
        if result == :end_of_stream, do: :stop, else: :continue

      {:DOWN, _ref, :process, _pid, _reason} ->
        :stop

      :terminate ->
        :stop
    end
    |> case do
      :continue -> receive_loop(native_ref, target)
      :stop -> :ok
    end
  end

  defp await_connection(native, target, url, timeout) do
    case await_open(native, url, timeout) do
      {:ok, native_ref} ->
        Logger.debug("Connection established @ #{url}")
        send(self(), :get_frame)
        send(target, {__MODULE__, :format_info_ready, native_ref})
        :continue

      {:error, :interrupted} ->
        :stop

      {:error, reason} ->
        raise "Failed to open input from #{url}. Reason: `#{reason}`"
    end
  end
end
