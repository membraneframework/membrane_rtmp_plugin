defmodule Membrane.RTMP.Source.Native do
  @moduledoc false
  use Unifex.Loader

  alias Membrane.Time

  @spec create(String.t(), Time.t()) :: {:ok, reference()} | {:error, reason :: any()}
  def create(url, timeout) do
    with {:ok, timeout} <- get_timeout(timeout),
         {:ok, native} <- native_create(url, timeout) do
      {:ok, native}
    else
      {:error, _reason} = error -> error
    end
  end

  @one_second Time.seconds(1)

  defp get_timeout(:infinity), do: {:ok, "0"}

  defp get_timeout(time) when rem(time, @one_second) != 0,
    do: {:error, "Timeout must be a multiply of one second. #{Time.pretty_duration(time)} is not"}

  defp get_timeout(time),
    do:
      Time.as_seconds(time)
      |> Ratio.trunc()
      |> inspect()
      |> then(&{:ok, &1})
end
