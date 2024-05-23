defmodule Membrane.RTMP.Source do
  @moduledoc """
  Membrane Element for receiving an RTMP stream. Acts as a RTMP Server.
  This implementation is limited to only AAC and H264 streams.
  """
  use Membrane.Source
  require Membrane.Logger
  alias Membrane.RTMP.Server.ClientHandler
  alias Membrane.RTMP.Source.DefaultBehaviourImplementation

  def_output_pad :output,
    availability: :always,
    accepted_format: Membrane.RemoteStream,
    flow_control: :manual,
    demand_unit: :buffers

  def_options client_handler: [spec: pid(), default: nil],
              url: [spec: String.t(), default: nil]

  defguardp is_builtin_server(opts)
            when not is_nil(opts.url) and is_nil(opts.client_handler)

  defguardp is_external_server(opts)
            when not is_nil(opts.client_handler) and
                   is_nil(opts.url)

  @impl true
  def handle_init(_ctx, opts) when is_builtin_server(opts) do
    state = %{
      app: nil,
      stream_key: nil,
      server: nil,
      url: opts.url,
      mode: :builtin_server,
      client_handler: nil,
      use_ssl?: nil
    }

    {[], state}
  end

  @impl true
  def handle_init(_ctx, opts) when is_external_server(opts) do
    state = %{
      mode: :external_server,
      client_handler: opts.client_handler
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

    listen_options =
      if state.use_ssl? do
        certfile = System.get_env("CERT_PATH")
        keyfile = System.get_env("CERT_KEY_PATH")

        [
          :binary,
          packet: :raw,
          active: false,
          certfile: certfile,
          keyfile: keyfile
        ]
      else
        [
          :binary,
          packet: :raw,
          active: false
        ]
      end

    {:ok, server_pid} =
      Membrane.RTMP.Server.start_link(%Membrane.RTMP.Server{
        behaviour: DefaultBehaviourImplementation,
        behaviour_options: %{controlling_process: self()},
        port: port,
        use_ssl?: use_ssl?,
        listen_options: listen_options
      })

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

    :ok = DefaultBehaviourImplementation.request_for_data(state.client_handler)

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
        %{client_handler: nil, mode: :builtin_server} = state
      ) do
    {[], state}
  end

  @impl true
  def handle_demand(
        :output,
        size,
        :buffers,
        _ctx,
        %{client_handler: client_handler, mode: :builtin_server} = state
      ) do
    :ok = ClientHandler.demand_data(client_handler, size)
    :ok = DefaultBehaviourImplementation.request_for_data(state.client_handler)
    {[], state}
  end

  @impl true
  def handle_demand(
        :output,
        size,
        :buffers,
        _ctx,
        %{client_handler: client_handler, mode: :external_server} = state
      ) do
    :ok = ClientHandler.demand_data(client_handler, size)
    {[], state}
  end

  @impl true
  def handle_info({:client_connected, app, stream_key}, _ctx, %{mode: :builtin_server} = state) do
    :ok = Membrane.RTMP.Server.subscribe(state.server, state.app, state.stream_key)
    state = %{state | app: app, stream_key: stream_key}
    {[], state}
  end

  @impl true
  def handle_info({:client_handler, client_handler_pid}, _ctx, %{mode: :builtin_server} = state) do
    {[redemand: :output], %{state | client_handler: client_handler_pid}}
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
      case String.split(uri.path, "/") do
        ["", app, stream_key] -> {app, stream_key}
        ["", app] -> {app, ""}
        _other -> {"", ""}
      end

    use_ssl? =
      case uri.scheme do
        "rtmp" -> false
        "rtmps" -> true
      end

    {use_ssl?, port, app, stream_key}
  end
end
