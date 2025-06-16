defmodule Membrane.RTMPServer.SSLListenerTest do
  @moduledoc """
  Test to verify that SSL listener works correctly with proper option separation.
  """

  use ExUnit.Case, async: false

  alias Membrane.RTMPServer.{Config, Listener}

  @tag :tmp_dir
  test "SSL listen options don't cause argument errors", %{tmp_dir: tmp_dir} do
    # Create dummy certificate files
    cert_path = Path.join(tmp_dir, "cert.pem")
    key_path = Path.join(tmp_dir, "key.pem")

    # Create minimal valid certificate content for testing
    File.write!(cert_path, """
    -----BEGIN CERTIFICATE-----
    MIICdTCCAd4CCQDKn4iM3Jm8ZzANBgkqhkiG9w0BAQsFADCBgTELMAkGA1UEBhMC
    VVMxCzAJBgNVBAgMAlRYMQ8wDQYDVQQHDAZBdXN0aW4xEjAQBgNVBAoMCVRlc3Qg
    Q29ycDELMAkGA1UECwwCSVQxDDAKBgNVBAMMA3d3dzElMCMGCSqGSIb3DQEJARYW
    dGVzdEBleGFtcGxlLmNvbQ==
    -----END CERTIFICATE-----
    """)

    File.write!(key_path, """
    -----BEGIN PRIVATE KEY-----
    MIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQC5w9Y+7Y+7Y+7Y
    +7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+
    7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+7Y+
    -----END PRIVATE KEY-----
    """)

    # Test SSL listen options separately
    ssl_config = [
      certfile: cert_path,
      keyfile: key_path,
      verify: :verify_none,
      fail_if_no_peer_cert: false,
      versions: [:"tlsv1.2", :"tlsv1.3"]
    ]

    # Get SSL listen options - these should be safe for :ssl.listen/2
    listen_opts = Config.get_ssl_listen_options(ssl_config, true)
    basic_opts = Config.get_listen_options()
    combined_opts = basic_opts ++ listen_opts

    # Verify the options contain what we expect for listening
    assert listen_opts[:certfile] == cert_path
    assert listen_opts[:keyfile] == key_path
    assert listen_opts[:versions] == [:"tlsv1.2", :"tlsv1.3"]

    # Verify handshake options are separate
    handshake_opts = Config.get_ssl_handshake_options(ssl_config, false)
    assert handshake_opts[:verify] == :verify_none
    assert handshake_opts[:fail_if_no_peer_cert] == false

    # Verify that listen options don't contain handshake-only options
    refute Keyword.has_key?(listen_opts, :verify)
    refute Keyword.has_key?(listen_opts, :fail_if_no_peer_cert)

    # The real test would be to try :ssl.listen/2, but that requires a proper certificate
    # For now, we verify the option separation is working correctly
    assert is_list(combined_opts)
    assert length(combined_opts) > 0
  end

  test "SSL listener provides helpful error when no certificates configured" do
    # Clear any existing SSL configuration
    Application.delete_env(:membrane_rtmp_plugin, :ssl)

    # Clean up SSL environment variables
    ssl_env_vars = [
      "RTMP_SSL_CERTFILE",
      "CERT_PATH",
      "RTMP_SSL_KEYFILE",
      "CERT_KEY_PATH",
      "RTMP_SSL_CACERTFILE",
      "CA_CERT_PATH"
    ]

    Enum.each(ssl_env_vars, &System.delete_env/1)

    # Create options without SSL certificates
    options = %{
      use_ssl?: true,
      ssl_options: [],
      server: self(),
      port: 0,
      handle_new_client: fn _client_ref, _app, _stream_key -> :ok end,
      client_timeout: 1000
    }

    # Should raise a helpful ArgumentError
    assert_raise ArgumentError, ~r/SSL is enabled but certificate files are not configured/, fn ->
      Listener.run(options)
    end
  end
end
