defmodule Membrane.RTMPServer.ConfigTest do
  use ExUnit.Case, async: false

  alias Membrane.RTMPServer.Config

  describe "get_ssl_options/1" do
    setup do
      # Clean up any existing config before each test
      Application.delete_env(:membrane_rtmp_plugin, :ssl)
      :ok
    end

    test "returns default options when no configuration is provided" do
      options = Config.get_ssl_options([], false)

      assert options[:verify] == :verify_none
      assert options[:fail_if_no_peer_cert] == false
      assert options[:versions] == [:"tlsv1.2"]
      assert options[:secure_renegotiate] == true
      assert options[:reuse_sessions] == true
    end

    test "merges application configuration with defaults" do
      Application.put_env(:membrane_rtmp_plugin, :ssl,
        certfile: "/app/cert.pem",
        keyfile: "/app/key.pem",
        verify: :verify_peer
      )

      options = Config.get_ssl_options([], false)

      assert options[:certfile] == "/app/cert.pem"
      assert options[:keyfile] == "/app/key.pem"
      assert options[:verify] == :verify_peer
      # Default options should still be present
      assert options[:fail_if_no_peer_cert] == false
      assert options[:versions] == [:"tlsv1.2"]
    end

    test "runtime options override application configuration" do
      Application.put_env(:membrane_rtmp_plugin, :ssl,
        certfile: "/app/cert.pem",
        verify: :verify_peer
      )

      runtime_opts = [
        certfile: "/runtime/cert.pem",
        keyfile: "/runtime/key.pem"
      ]

      options = Config.get_ssl_options(runtime_opts, false)

      assert options[:certfile] == "/runtime/cert.pem"
      assert options[:keyfile] == "/runtime/key.pem"
      # App config should still be applied for non-overridden options
      assert options[:verify] == :verify_peer
    end
  end

  describe "get_listen_options/0" do
    test "returns basic socket options" do
      options = Config.get_listen_options()

      assert :binary in options
      assert options[:packet] == :raw
      assert options[:active] == false
      assert options[:reuseaddr] == true
    end
  end

  describe "validate_ssl_options/1" do
    @tag :tmp_dir
    test "validates existing certificate files", %{tmp_dir: tmp_dir} do
      cert_path = Path.join(tmp_dir, "cert.pem")
      key_path = Path.join(tmp_dir, "key.pem")

      File.write!(cert_path, "dummy cert")
      File.write!(key_path, "dummy key")

      options = [certfile: cert_path, keyfile: key_path]
      validated = Config.validate_ssl_options(options)

      assert validated == options
    end

    test "raises error for non-existent certificate file" do
      options = [certfile: "/non/existent/cert.pem", keyfile: "/non/existent/key.pem"]

      assert_raise ArgumentError, ~r/SSL certificate file does not exist/, fn ->
        Config.validate_ssl_options(options)
      end
    end

    @tag :tmp_dir
    test "raises error for missing key file when cert is provided", %{tmp_dir: tmp_dir} do
      cert_path = Path.join(tmp_dir, "cert.pem")
      File.write!(cert_path, "dummy cert")

      options = [certfile: cert_path]

      assert_raise ArgumentError, ~r/SSL certificate file provided but key file is missing/, fn ->
        Config.validate_ssl_options(options)
      end
    end

    test "doesn't allow options without certificate file" do
      options = []

      assert_raise ArgumentError, ~r/SSL certificate file is not configured/, fn ->
        Config.validate_ssl_options(options)
      end
    end
  end

  describe "get_ssl_config_summary/1" do
    setup do
      # Clean up any existing config before each test
      Application.delete_env(:membrane_rtmp_plugin, :ssl)
      :ok
    end

    test "provides comprehensive configuration overview" do
      # Set up different configuration sources
      Application.put_env(:membrane_rtmp_plugin, :ssl,
        certfile: "/app/cert.pem",
        verify: :verify_peer
      )

      runtime_opts = [keyfile: "/runtime/key.pem", versions: [:"tlsv1.3"]]

      summary = Config.get_ssl_config_summary(runtime_opts)

      # Check that all configuration sources are represented
      assert is_list(summary.defaults)
      assert is_list(summary.app_config)
      assert is_list(summary.runtime)
      assert is_list(summary.final)

      # Verify app config
      assert summary.app_config[:certfile] == "/app/cert.pem"
      assert summary.app_config[:verify] == :verify_peer

      # Verify runtime config
      assert summary.runtime[:keyfile] == "/runtime/key.pem"
      assert summary.runtime[:versions] == [:"tlsv1.3"]

      # Verify final config has proper priority
      # Runtime overrides defaults
      assert summary.final[:keyfile] == "/runtime/key.pem"
      # From app config
      assert summary.final[:verify] == :verify_peer
      # From runtime
      assert summary.final[:versions] == [:"tlsv1.3"]
    end
  end

  describe "SSL configuration validation" do
    test "validates TLS versions" do
      options = [versions: [:invalid_version]]

      assert_raise ArgumentError, ~r/Invalid TLS versions/, fn ->
        Config.validate_ssl_options(options, false)
      end
    end

    test "validates verify option" do
      options = [verify: :invalid_verify]

      assert_raise ArgumentError, ~r/Invalid verify option/, fn ->
        Config.validate_ssl_options(options, false)
      end
    end

    test "accepts valid configuration" do
      options = [
        versions: [:"tlsv1.2", :"tlsv1.3"],
        verify: :verify_peer,
        log_level: :info
      ]

      validated = Config.validate_ssl_options(options, false)
      assert validated == options
    end
  end

  describe "certificate path processing" do
    @tag :tmp_dir
    test "expands relative paths", %{tmp_dir: tmp_dir} do
      cert_name = "test_cert.pem"
      File.write!(Path.join(tmp_dir, cert_name), "dummy cert")

      # Change to tmp_dir to test relative path resolution
      original_cwd = File.cwd!()
      File.cd!(tmp_dir)

      try do
        options = [certfile: cert_name]
        processed = Config.get_ssl_options(options, false)

        # Should be expanded to absolute path
        assert Path.absname(processed[:certfile]) == processed[:certfile]
        assert String.ends_with?(processed[:certfile], cert_name)
      after
        File.cd!(original_cwd)
      end
    end

    @tag :tmp_dir
    test "validates additional certificate files", %{tmp_dir: tmp_dir} do
      cert_path = Path.join(tmp_dir, "cert.pem")
      key_path = Path.join(tmp_dir, "key.pem")
      ca_path = Path.join(tmp_dir, "ca.pem")

      File.write!(cert_path, "dummy cert")
      File.write!(key_path, "dummy key")
      # Don't create CA file to test validation

      options = [
        certfile: cert_path,
        keyfile: key_path,
        cacertfile: ca_path
      ]

      assert_raise ArgumentError, ~r/SSL CA certificate file does not exist/, fn ->
        Config.validate_ssl_options(options, true)
      end
    end
  end

  describe "SSL listen vs handshake options" do
    setup do
      # Clean up any existing config before each test
      Application.delete_env(:membrane_rtmp_plugin, :ssl)
      :ok
    end

    test "get_ssl_listen_options includes certificate and basic SSL options" do
      options =
        Config.get_ssl_listen_options(
          [
            certfile: "/path/cert.pem",
            keyfile: "/path/key.pem",
            verify: :verify_peer,
            versions: [:"tlsv1.3"],
            honor_cipher_order: true
          ],
          false
        )

      # Should include certificate options for SSL context
      assert options[:certfile] == "/path/cert.pem"
      assert options[:keyfile] == "/path/key.pem"
      assert options[:versions] == [:"tlsv1.3"]

      # Should NOT include handshake-specific options
      refute Keyword.has_key?(options, :verify)
      refute Keyword.has_key?(options, :honor_cipher_order)
    end

    test "get_ssl_handshake_options includes verification and connection options" do
      options =
        Config.get_ssl_handshake_options(
          [
            certfile: "/path/cert.pem",
            keyfile: "/path/key.pem",
            verify: :verify_peer,
            versions: [:"tlsv1.3"],
            honor_cipher_order: true,
            fail_if_no_peer_cert: true
          ],
          false
        )

      # Should include handshake options
      assert options[:verify] == :verify_peer
      assert options[:versions] == [:"tlsv1.3"]
      assert options[:honor_cipher_order] == true
      assert options[:fail_if_no_peer_cert] == true

      # Should NOT include certificate file paths (these should be in listen options)
      refute Keyword.has_key?(options, :certfile)
      refute Keyword.has_key?(options, :keyfile)
    end

    test "listen and handshake options are complementary" do
      full_config = [
        certfile: "/path/cert.pem",
        keyfile: "/path/key.pem",
        cacertfile: "/path/ca.pem",
        verify: :verify_peer,
        versions: [:"tlsv1.3"],
        honor_cipher_order: true,
        fail_if_no_peer_cert: true,
        secure_renegotiate: true
      ]

      listen_opts = Config.get_ssl_listen_options(full_config, false)
      handshake_opts = Config.get_ssl_handshake_options(full_config, false)

      # Ensure no overlap in critical options
      listen_keys = Keyword.keys(listen_opts)
      handshake_keys = Keyword.keys(handshake_opts)

      # These should only appear in listen options
      assert :certfile in listen_keys
      assert :keyfile in listen_keys
      refute :certfile in handshake_keys
      refute :keyfile in handshake_keys

      # These should only appear in handshake options
      assert :verify in handshake_keys
      assert :honor_cipher_order in handshake_keys
      refute :verify in listen_keys
      refute :honor_cipher_order in listen_keys

      # These can appear in both
      assert :versions in listen_keys
      assert :versions in handshake_keys
      # Needed for verification
      assert :cacertfile in handshake_keys
    end
  end
end
