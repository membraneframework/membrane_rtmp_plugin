defmodule Membrane.RTMP.Source do
  @moduledoc """
  Membrane Element for receiving an RTMP stream. Acts as a RTMP Server.
  This implementation is limited to only AAC and H264 streams.

  The source can be used in the following two scenarios:
  * by providing the URL on which the client is expected to connect - note, that if the client doesn't
  connect on this URL, the source won't complete its setup
  * by spawning `Membrane.RTMP.Server`, subscribing for a given app and stream key on which the client
  will connect, waiting for a client reference and passing the client reference to the `#{inspect(__MODULE__)}`.
  """
  use Membrane.Source
  require Membrane.Logger
  alias __MODULE__.ClientHandler, as: SourceClientHandler
  alias Membrane.RTMP.Server.ClientHandler

  def_output_pad :output,
    availability: :always,
    accepted_format: Membrane.RemoteStream,
    flow_control: :manual,
    demand_unit: :buffers

  def_options client_ref: [
                default: nil,
                spec: pid(),
                description: """
                A pid of a process acting as a client reference.
                Can be gained with the use of `Membrane.RTMP.Server`.
                """
              ],
              url: [
                default: nil,
                spec: String.t(),
                description: """
                An URL on which the client is expected to connect, for example:
                rtmp://127.0.0.1:1935/app/stream_key
                """
              ]

  defguardp is_builtin_server(opts)
            when not is_nil(opts.url) and is_nil(opts.client_ref)

  defguardp is_external_server(opts)
            when not is_nil(opts.client_ref) and
                   is_nil(opts.url)

  @impl true
  def handle_init(_ctx, opts) when is_builtin_server(opts) do
    state = %{
      app: nil,
      stream_key: nil,
      server: nil,
      url: opts.url,
      mode: :builtin_server,
      client_ref: nil,
      use_ssl?: nil
    }

    {[], state}
  end

  @impl true
  def handle_init(_ctx, opts) when is_external_server(opts) do
    state = %{
      mode: :external_server,
      client_ref: opts.client_ref
    }

    {[], state}
  end

  @impl true
  def handle_init(_ctx, opts) do
    raise """
    Improper options passed to the `#{__MODULE__}`:
    #{inspect(opts)}
    """
  end

  @impl true
  def handle_setup(_ctx, %{mode: :builtin_server} = state) do
    {use_ssl?, port, app, stream_key} = parse_url(state.url)

    {:ok, server_pid} =
      Membrane.RTMP.Server.start_link(
        handler: %SourceClientHandler{controlling_process: self()},
        port: port,
        use_ssl?: use_ssl?
      )

    state = %{state | app: app, stream_key: stream_key, server: server_pid}
    {[], state}
  end

  @impl true
  def handle_setup(_ctx, %{mode: :external_server} = state) do
    {[], state}
  end

  @impl true
  def handle_playing(_ctx, %{mode: :external_server} = state) do
    stream_format = [
      stream_format:
        {:output, %Membrane.RemoteStream{content_format: Membrane.FLV, type: :bytestream}}
    ]

    :ok = SourceClientHandler.request_for_data(state.client_ref)

    {stream_format, state}
  end

  @impl true
  def handle_playing(_ctx, %{mode: :builtin_server} = state) do
    stream_format = [
      stream_format:
        {:output, %Membrane.RemoteStream{content_format: Membrane.FLV, type: :bytestream}}
    ]

    {stream_format, state}
  end

  @impl true
  def handle_demand(
        :output,
        _size,
        :buffers,
        _ctx,
        %{client_ref: nil, mode: :builtin_server} = state
      ) do
    {[], state}
  end

  @impl true
  def handle_demand(
        :output,
        size,
        :buffers,
        _ctx,
        %{client_ref: client_ref, mode: :builtin_server} = state
      ) do
    :ok = ClientHandler.demand_data(client_ref, size)
    :ok = SourceClientHandler.request_for_data(client_ref)
    {[], state}
  end

  @impl true
  def handle_demand(
        :output,
        size,
        :buffers,
        _ctx,
        %{client_ref: client_ref, mode: :external_server} = state
      ) do
    :ok = ClientHandler.demand_data(client_ref, size)
    {[], state}
  end

  @impl true
  def handle_info({:client_connected, app, stream_key}, _ctx, %{mode: :builtin_server} = state) do
    :ok = Membrane.RTMP.Server.subscribe_any(state.server)
    state = %{state | app: app, stream_key: stream_key}
    {[], state}
  end

  @impl true
  def handle_info(
        {:client_ref, client_ref_pid, _app, _stream_key},
        _ctx,
        %{mode: :builtin_server} = state
      ) do
    {[redemand: :output], %{state | client_ref: client_ref_pid}}
  end

  @impl true
  def handle_info({:data, data}, _ctx, state) do
    {[buffer: {:output, %Membrane.Buffer{payload: data}}, redemand: :output], state}
  end

  @impl true
  def handle_info(:end_of_stream, ctx, state) do
    if ctx.pads[:output].end_of_stream? do
      {[], state}
    else
      {[end_of_stream: :output], state}
    end
  end

  @impl true
  def handle_terminate_request(_ctx, state) do
    {[terminate: :normal], state}
  end

  defp parse_url(url) do
    uri = URI.parse(url)
    port = uri.port

    {app, stream_key} =
      case String.trim_leading(uri.path, "/") |> String.trim_trailing("/") |> String.split("/") do
        [app, stream_key] -> {app, stream_key}
        [app] -> {app, ""}
      end

    use_ssl? =
      case uri.scheme do
        "rtmp" -> false
        "rtmps" -> true
      end

    {use_ssl?, port, app, stream_key}
  end
end
