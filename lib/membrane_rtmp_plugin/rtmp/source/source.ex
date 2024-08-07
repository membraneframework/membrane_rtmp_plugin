defmodule Membrane.RTMP.Source do
  @moduledoc """
  Membrane Element for receiving an RTMP stream. Acts as a RTMP Server.
  This implementation is limited to only AAC and H264 streams.

  The source can be used in the following two scenarios:
  * by providing the URL on which the client is expected to connect - note, that if the client doesn't
  connect on this URL, the source won't complete its setup. Note that all attempted connections to
  other `app` or `stream_key` than specified ones will be rejected.

  * by spawning `Membrane.RTMP.Server`, receiving a client reference and passing it to the `#{inspect(__MODULE__)}`.
  """
  use Membrane.Source
  require Membrane.Logger
  require Logger
  alias __MODULE__.SourceClientHandler
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
    {use_ssl?, port, app, stream_key} = Membrane.RTMPServer.parse_url(state.url)

    parent_pid = self()

    new_client_callback = fn client_ref, app, stream_key ->
      send(parent_pid, {:client_ref, client_ref, app, stream_key})
    end

    {:ok, server_pid} =
      Membrane.RTMP.Server.start_link(
        handler: %SourceClientHandler{controlling_process: self()},
        port: port,
        use_ssl?: use_ssl?,
        new_client_callback: new_client_callback,
        client_timeout: 100
      )

    state = %{state | app: app, stream_key: stream_key, server: server_pid}
    {[setup: :incomplete], state}
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
  def handle_info(
        {:client_ref, client_ref, app, stream_key},
        _ctx,
        %{mode: :builtin_server} = state
      )
      when app == state.app and stream_key == state.stream_key do
    {[setup: :complete], %{state | client_ref: client_ref}}
  end

  @impl true
  def handle_info(
        {:client_ref, _client_ref, app, stream_key},
        _ctx,
        %{mode: :builtin_server} = state
      ) do
    Logger.warning("Unexpected client connected on /#{app}/#{stream_key}")
    {[], state}
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
end
