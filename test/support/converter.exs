Mix.install([
  :membrane_stream_plugin,
  :membrane_h264_format,
  :membrane_file_plugin
])

defmodule MembraneStreamH264Filter do
  use Membrane.Filter

  def_input_pad :input,
    demand_unit: :buffers,
    demand_mode: :auto,
    accepted_format: _any

  def_output_pad :output,
    demand_mode: :auto,
    accepted_format: _any

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    {[stream_format: {:output, Map.put(stream_format, :stream_structure, :annexb)}], state}
  end

  @impl true
  def handle_process(:input, buffer, _ctx, state) do
    buffer =
      update_in(
        buffer.metadata.h264.nalus,
        &Enum.map(&1, fn nalu -> Map.drop(nalu, [:prefixed_poslen, :unprefixed_poslen]) end)
      )

    {[buffer: {:output, buffer}], state}
  end
end

defmodule MembraneStreamAACFilter do
  use Membrane.Filter

  def_input_pad :input,
    demand_unit: :buffers,
    demand_mode: :auto,
    accepted_format: _any

  def_output_pad :output,
    demand_mode: :auto,
    accepted_format: _any

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    {[stream_format: {:output, Map.put(stream_format, :config, nil)}], state}
  end

  @impl true
  def handle_process(:input, buffer, _ctx, state) do
    {[buffer: {:output, buffer}], state}
  end
end

defmodule ConversionPipeline do
  use Membrane.Pipeline

  import Membrane.ChildrenSpec

  @impl true
  def handle_init(_ctx, opts) do
    structure = [
      child(:source, %Membrane.File.Source{location: opts.input_location})
      |> child(:deserializer, Membrane.Stream.Deserializer)
      |> child(:filter, MembraneStreamH264Filter)
      |> child(:serializer, Membrane.Stream.Serializer)
      |> child(:sink, %Membrane.File.Sink{location: opts.output_location})
    ]

    {[spec: structure], %{children_with_eos: MapSet.new()}}
  end

  @impl true
  def handle_element_end_of_stream(element, _pad, _ctx, state) do
    state = %{state | children_with_eos: MapSet.put(state.children_with_eos, element)}

    actions =
      if :sink in state.children_with_eos,
        do: [terminate: :shutdown],
        else: []

    {actions, state}
  end
end

opts = %{
  input_location: "test/fixtures/audio.msr",
  output_location: "audio.msr"
}

{:ok, _supervisor_pid, pipeline_pid} = ConversionPipeline.start(opts)
ref = Process.monitor(pipeline_pid)

receive do
  {:DOWN, ^ref, :process, _pipeline_pid, _reason} ->
    :ok
end
