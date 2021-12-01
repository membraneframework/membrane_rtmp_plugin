defmodule Membrane.RTMP.Source do
  @moduledoc """
  Membrane Element being a server-side source of RTMP streams.

  Implementation based on FFmpeg
  """
  use Membrane.Source
  alias __MODULE__.Native
  alias Membrane.{AVC, Time, AAC, Buffer}
  require Membrane.Logger

  def_output_pad :audio,
    availability: :always,
    caps: {AAC, encapsulation: :none},
    mode: :pull

  def_output_pad :video,
    availability: :always,
    caps: :any,
    mode: :pull

  def_options url: [
                spec: binary(),
                description: """
                URL on which the FFmpeg instance will be created
                """
              ],
              timeout: [
                spec: Time.t() | :infinity,
                default: :infinity,
                description: """
                Time the server will wait for connection from the client

                Duration given must be a multiply of one second or atom `:infinity`.
                """
              ],
              max_buffer_size: [
                spec: non_neg_integer(),
                default: 1024
              ]

  @impl true
  def handle_init(%__MODULE__{} = opts) do
    {:ok,
     Map.from_struct(opts)
     |> Map.merge(%{native: nil, provider: nil, buffers: %{video: Qex.new(), audio: Qex.new()}})}
  end

  @impl true
  def handle_prepared_to_playing(_ctx, state) do
    # Native.create is blocking. Hence, the element will only go from prepared to playing when a new connection is established.
    # This might not be desirable, but unfortunately this is caused by the fact that FFmpeg's create_input_stream is awaiting a new connection from the client before returning.

    case Native.create(state.url, state.timeout) do
      {:ok, native} ->
        Membrane.Logger.debug("Connection established @ #{state.url}")
        state = Map.put(state, :native, native)
        pid = spawn(__MODULE__, :frame_provider, [native, self()])
        Process.link(pid)
        {{:ok, get_params(native)}, %{state | provider: pid}}

      {:error, reason} ->
        raise("Transition to state `playing` failed. Reason: `#{reason}`")
    end
  end

  @impl true
  def handle_demand(pad, _size, _unit, _ctx, state) do
    {actions, state} = maybe_provide_frame(pad, state)
    send(state.provider, :get_frame)
    {{:ok, actions}, state}
  end

  defp maybe_provide_frame(type, state) do
    buffer = get_in(state, [:buffers, type])

    {actions, queue} =
      case Qex.pop(buffer) do
        {:empty, queue} -> {[], queue}
        {{:value, buffer}, queue} -> {[buffer: {type, buffer}, redemand: type], queue}
      end

    state = put_in(state, [:buffers, type], queue)
    {actions, state}
  end

  @impl true
  def handle_other({:result, result}, ctx, state) when ctx.playback_state == :playing do
    case result do
      {:ok, type, timestamp, frame} ->
        timestamp = Membrane.Time.microseconds(timestamp)
        payload = prepare_payload(type, frame)
        buffer = %Buffer{pts: timestamp, metadata: %{timestamp: timestamp}, payload: payload}
        state = update_in(state, [:buffers, type], &Qex.push(&1, buffer))
        other = if type == :video, do: :audio, else: :video

        {{:ok, redemand: other}, state}

      :end_of_stream ->
        {{:ok, end_of_stream: :audio, end_of_stream: :video}, state}

      {:error, reason} ->
        raise("Fetching frame failed. Reason: `#{reason}`")
    end
  end

  @impl true
  def handle_other({:result, _result}, _ctx, state) do
    {:ok, state}
  end

  @spec frame_provider(reference(), pid()) :: :ok
  def frame_provider(native, target) do
    receive do
      :terminate ->
        Native.stop(native)
        :ok
    after
      0 ->
        receive do
          :get_frame ->
            result = Native.read_frame(native)
            send(target, {:result, result})

            if result == :end_of_stream, do: :ok, else: frame_provider(native, target)

          :terminate ->
            Native.stop(native)
            :ok
        end
    end
  end

  @impl true
  def handle_playing_to_prepared(_ctx, state) do
    send(state.provider, :terminate)
    {:ok, %{state | native: nil}}
  end

  defp prepare_payload(:video, payload), do: AVC.Utils.to_annex_b(payload)
  defp prepare_payload(:audio, payload), do: payload

  defp get_params(native),
    do:
      [
        get_audio_params(native),
        get_video_params(native)
      ]
      |> Enum.concat()

  defp get_audio_params(native) do
    with {:ok, asc} <- Native.get_audio_params(native),
         {:ok, caps} <- get_aac_caps(asc) do
      [caps: {:audio, caps}]
    else
      {:error, _reason} -> []
    end
  end

  defp get_video_params(native) do
    with {:ok, config} <- Native.get_video_params(native),
         {:ok, parsed} <- AVC.Configuration.parse(config),
         %AVC.Configuration{pps: [pps], sps: [sps]} = parsed do
      [buffer: {:video, %Buffer{payload: <<0, 0, 1>> <> sps <> <<0, 0, 1>> <> pps}}]
    else
      {:error, _reason} -> []
    end
  end

  defp get_aac_caps(
         <<profile::5, sr_index::4, channel_configuration::4, frame_length_flag::1, _rest::bits>> =
           _audio_specific_config
       ),
       do:
         %AAC{
           profile: AAC.aot_id_to_profile(profile),
           mpeg_version: 4,
           sample_rate: AAC.sampling_frequency_id_to_sample_rate(sr_index),
           channels: AAC.channel_config_id_to_channels(channel_configuration),
           encapsulation: :none,
           samples_per_frame: if(frame_length_flag == 1, do: 1024, else: 960)
         }
         |> then(&{:ok, &1})

  defp get_aac_caps(_otherwise), do: {:error, :unknown_pattern}
end
