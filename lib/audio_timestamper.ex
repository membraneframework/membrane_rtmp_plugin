defmodule Membrane.AAC.Timestamper do
  use Membrane.Filter
  use Bunch

  alias Membrane.{AAC, Time}

  def_input_pad :input,
    mode: :push,
    availability: :always,
    caps: {AAC, encapsulation: :none}

  def_output_pad :output,
    mode: :push,
    availability: :always,
    caps: {AAC, encapsulation: :none}

  @impl true
  def handle_init(_opts) do
    {:ok, %{timestamp: 0, partial: <<>>}}
  end

  @impl true
  def handle_process(:input, buffer, ctx, state) do
    caps = ctx.pads.input.caps
    metadata = Map.put(buffer.metadata, :timestamp, state.timestamp)
    buffer = %{buffer | metadata: metadata}
    state = Map.update!(state, :timestamp, &next_timestamp(&1, caps))
    {{:ok, buffer: {:output, buffer}}, state}
  end

  defp next_timestamp(timestamp, caps) do
    use Ratio

    timestamp +
      Ratio.new(caps.samples_per_frame * caps.frames_per_buffer * Time.second(), caps.sample_rate)
  end
end
