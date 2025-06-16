defmodule Membrane.RTMPServer.Config do
  @moduledoc """
  Configuration module for RTMP server SSL settings.

  This module provides functions to retrieve SSL configuration from two sources:
  - Application configuration (:membrane_rtmp_plugin app config)
  - Runtime options (highest priority)

  ## Configuration Options

  SSL options can be configured in your application config:

      config :membrane_rtmp_plugin, :ssl,
        certfile: "/path/to/cert.pem",
        keyfile: "/path/to/key.pem",
        verify: :verify_none,
        fail_if_no_peer_cert: false,
        versions: [:"tlsv1.2", :"tlsv1.3"],
        ciphers: :ssl.cipher_suites(:default, :"tlsv1.2"),
        honor_cipher_order: true,
        # Additional certificate configuration
        cacertfile: "/path/to/ca-bundle.pem",
        certchain: "/path/to/cert-chain.pem",
        password: "cert_password",
        # Advanced SSL options
        alpn_advertised_protocols: ["h2", "http/1.1"],
        alpn_preferred_protocols: ["h2", "http/1.1"],
        sni_hosts: [],
        log_level: :notice
  """

  @type ssl_option ::
          {:certfile, Path.t()}
          | {:keyfile, Path.t()}
          | {:verify, :verify_none | :verify_peer}
          | {:fail_if_no_peer_cert, boolean()}
          | {:versions, [:ssl.tls_version()]}
          | {:ciphers, [:ssl.cipher()]}
          | {:honor_cipher_order, boolean()}
          | {:secure_renegotiate, boolean()}
          | {:reuse_sessions, boolean()}
          | {:cacertfile, Path.t()}
          | {:certchain, Path.t()}
          | {:depth, non_neg_integer()}
          | {:password, String.t()}
          | {:alpn_advertised_protocols, [String.t()]}
          | {:alpn_preferred_protocols, [String.t()]}
          | {:sni_hosts, keyword()}
          | {:log_level, :ssl.log_level()}

  @type ssl_options :: [ssl_option()]

  @doc """
  Gets SSL options for the listener socket.

  Priority order:
  1. Runtime options passed to the function
  2. Application configuration (:membrane_rtmp_plugin, :ssl)
  3. Default SSL options
  """
  @spec get_ssl_options(runtime_opts :: ssl_options(), validate_files :: boolean()) ::
          ssl_options()
  def get_ssl_options(runtime_opts \\ [], validate_files \\ true) do
    default_opts = get_default_ssl_options()
    app_config_opts = get_app_config_ssl_options()

    default_opts
    |> Keyword.merge(app_config_opts)
    |> Keyword.merge(runtime_opts)
    |> process_certificate_paths()
    |> validate_ssl_options(validate_files)
  end

  @doc """
  Gets SSL options specifically for the SSL listen socket.
  This excludes certificate files and handshake-specific options that should only be used during handshake.
  """
  @spec get_ssl_listen_options(runtime_opts :: ssl_options(), validate_files :: boolean()) ::
          ssl_options()
  def get_ssl_listen_options(runtime_opts \\ [], validate_files \\ true) do
    all_opts = get_ssl_options(runtime_opts, validate_files)

    # Only include options that are known to work with :ssl.listen/2
    # Based on Erlang/OTP ssl documentation
    ssl_listen_opts =
      all_opts
      |> Keyword.take([
        :certfile,
        :keyfile,
        :cacertfile,
        :password,
        :versions
      ])

    # Ensure we have the minimum required options
    if ssl_listen_opts == [] do
      []
    else
      ssl_listen_opts
    end
  end

  @doc """
  Gets SSL options specifically for the SSL handshake.
  This includes verification and connection-specific options.
  """
  @spec get_ssl_handshake_options(runtime_opts :: ssl_options(), validate_files :: boolean()) ::
          ssl_options()
  def get_ssl_handshake_options(runtime_opts \\ [], validate_files \\ false) do
    get_ssl_options(runtime_opts, validate_files)
    |> Keyword.take([
      :verify,
      :fail_if_no_peer_cert,
      :versions,
      :ciphers,
      :honor_cipher_order,
      :secure_renegotiate,
      :reuse_sessions,
      :cacertfile,
      :depth,
      :log_level
    ])
  end

  @doc """
  Gets the basic socket options for listening (non-SSL specific).
  """
  @spec get_listen_options() :: [:inet.socket_option()]
  def get_listen_options() do
    [
      :binary,
      packet: :raw,
      active: false,
      reuseaddr: true
    ]
  end

  @doc """
  Validates that required SSL files exist and options are valid.
  Set validate_files to false to skip file existence checks (useful for testing).
  """
  @spec validate_ssl_options(ssl_options(), validate_files :: boolean()) :: ssl_options()
  def validate_ssl_options(opts, validate_files \\ true) do
    opts = validate_certificate_files(opts, validate_files)
    opts = validate_ssl_configuration(opts)
    opts
  end

  @doc """
  Gets a summary of the current SSL configuration from all sources.
  Useful for debugging configuration issues.
  """
  @spec get_ssl_config_summary(runtime_opts :: ssl_options()) :: %{
          defaults: ssl_options(),
          app_config: ssl_options(),
          runtime: ssl_options(),
          final: ssl_options()
        }
  def get_ssl_config_summary(runtime_opts \\ []) do
    defaults = get_default_ssl_options()
    app_config = get_app_config_ssl_options()
    final = get_ssl_options(runtime_opts, false)

    %{
      defaults: defaults,
      app_config: app_config,
      runtime: runtime_opts,
      final: final
    }
  end

  # Private functions

  @spec get_default_ssl_options() :: ssl_options()
  defp get_default_ssl_options() do
    [
      verify: :verify_none,
      fail_if_no_peer_cert: false,
      # Use only TLS 1.2 for better compatibility
      versions: [:"tlsv1.2"],
      secure_renegotiate: true,
      reuse_sessions: true,
      # More verbose logging to debug handshake issues
      log_level: :info
    ]
  end

  @spec get_app_config_ssl_options() :: ssl_options()
  defp get_app_config_ssl_options() do
    Application.get_env(:membrane_rtmp_plugin, :ssl, [])
  end

  @spec process_certificate_paths(ssl_options()) :: ssl_options()
  defp process_certificate_paths(opts) do
    opts
    |> expand_certificate_paths()
    |> resolve_relative_paths()
  end

  @spec expand_certificate_paths(ssl_options()) :: ssl_options()
  defp expand_certificate_paths(opts) do
    opts
    |> maybe_expand_path(:certfile)
    |> maybe_expand_path(:keyfile)
    |> maybe_expand_path(:cacertfile)
    |> maybe_expand_path(:certchain)
  end

  @spec maybe_expand_path(ssl_options(), atom()) :: ssl_options()
  defp maybe_expand_path(opts, key) do
    case opts[key] do
      nil -> opts
      path when is_binary(path) -> Keyword.put(opts, key, Path.expand(path))
      _other -> opts
    end
  end

  @spec resolve_relative_paths(ssl_options()) :: ssl_options()
  defp resolve_relative_paths(opts) do
    # If certificate files are specified with relative paths,
    # try to resolve them relative to the app's priv directory
    priv_dir = Application.app_dir(:membrane_rtmp_plugin, "priv")

    opts
    |> maybe_resolve_relative_to_priv(:certfile, priv_dir)
    |> maybe_resolve_relative_to_priv(:keyfile, priv_dir)
    |> maybe_resolve_relative_to_priv(:cacertfile, priv_dir)
    |> maybe_resolve_relative_to_priv(:certchain, priv_dir)
  end

  @spec maybe_resolve_relative_to_priv(ssl_options(), atom(), String.t()) :: ssl_options()
  defp maybe_resolve_relative_to_priv(opts, key, priv_dir) do
    case opts[key] do
      nil ->
        opts

      path when is_binary(path) ->
        resolve_path_relative_to_priv(opts, key, path, priv_dir)

      _other ->
        opts
    end
  end

  @spec resolve_path_relative_to_priv(ssl_options(), atom(), String.t(), String.t()) ::
          ssl_options()
  defp resolve_path_relative_to_priv(opts, key, path, priv_dir) do
    if Path.absname(path) == path do
      # Already absolute
      opts
    else
      priv_path = Path.join(priv_dir, path)

      if File.exists?(priv_path) do
        Keyword.put(opts, key, priv_path)
      else
        # Keep original path
        opts
      end
    end
  end

  @spec validate_certificate_files(ssl_options(), boolean()) :: ssl_options()
  defp validate_certificate_files(opts, validate_files) do
    case {opts[:certfile], opts[:keyfile]} do
      {nil, nil} ->
        opts

      {certfile, keyfile} when is_binary(certfile) and is_binary(keyfile) ->
        validate_cert_and_key_files(opts, validate_files, certfile, keyfile)

      {certfile, nil} when is_binary(certfile) ->
        validate_single_cert_file(
          validate_files,
          "SSL certificate file provided but key file is missing"
        )

        opts

      {nil, keyfile} when is_binary(keyfile) ->
        validate_single_cert_file(
          validate_files,
          "SSL key file provided but certificate file is missing"
        )

        opts
    end
  end

  @spec validate_cert_and_key_files(ssl_options(), boolean(), String.t(), String.t()) ::
          ssl_options()
  defp validate_cert_and_key_files(opts, validate_files, certfile, keyfile) do
    if validate_files do
      validate_file_exists(certfile, "SSL certificate")
      validate_file_exists(keyfile, "SSL key")
      validate_additional_cert_files(opts)
    end

    opts
  end

  @spec validate_additional_cert_files(ssl_options()) :: :ok
  defp validate_additional_cert_files(opts) do
    if opts[:cacertfile], do: validate_file_exists(opts[:cacertfile], "SSL CA certificate")
    if opts[:certchain], do: validate_file_exists(opts[:certchain], "SSL certificate chain")
    :ok
  end

  @spec validate_single_cert_file(boolean(), String.t()) :: :ok
  defp validate_single_cert_file(validate_files, error_message) do
    if validate_files do
      raise ArgumentError, error_message
    end

    :ok
  end

  @spec validate_file_exists(String.t(), String.t()) :: :ok
  defp validate_file_exists(file_path, file_type) do
    unless File.exists?(file_path) do
      raise ArgumentError, "#{file_type} file does not exist: #{file_path}"
    end

    :ok
  end

  @spec validate_ssl_configuration(ssl_options()) :: ssl_options()
  defp validate_ssl_configuration(opts) do
    # Validate TLS versions
    if versions = opts[:versions] do
      valid_versions = [:tlsv1, :"tlsv1.1", :"tlsv1.2", :"tlsv1.3"]
      invalid_versions = versions -- valid_versions

      unless Enum.empty?(invalid_versions) do
        raise ArgumentError,
              "Invalid TLS versions: #{inspect(invalid_versions)}. " <>
                "Valid versions are: #{inspect(valid_versions)}"
      end
    end

    # Validate verify option
    if verify = opts[:verify] do
      unless verify in [:verify_none, :verify_peer] do
        raise ArgumentError,
              "Invalid verify option: #{inspect(verify)}. " <>
                "Must be :verify_none or :verify_peer"
      end
    end

    # Validate log level
    if log_level = opts[:log_level] do
      valid_levels = [:none, :error, :warning, :notice, :info, :debug, :all]

      unless log_level in valid_levels do
        raise ArgumentError,
              "Invalid SSL log level: #{inspect(log_level)}. " <>
                "Valid levels are: #{inspect(valid_levels)}"
      end
    end

    opts
  end
end
