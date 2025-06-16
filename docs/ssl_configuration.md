# SSL Configuration for Membrane RTMP Plugin

This document shows how to configure SSL options for the RTMP server, including certificate paths and advanced SSL settings.

## Application Configuration (config/config.exs)

### Basic SSL Configuration
```elixir
import Config

config :membrane_rtmp_plugin, :ssl,
  certfile: "/path/to/your/certificate.pem",
  keyfile: "/path/to/your/private_key.pem",
  verify: :verify_none,
  fail_if_no_peer_cert: false
```

### Advanced SSL Configuration
```elixir
config :membrane_rtmp_plugin, :ssl,
  # Certificate files
  certfile: "/path/to/your/certificate.pem",
  keyfile: "/path/to/your/private_key.pem",
  cacertfile: "/path/to/ca-bundle.pem",
  certchain: "/path/to/cert-chain.pem",
  password: "certificate_password",

  # SSL verification settings
  verify: :verify_peer,
  fail_if_no_peer_cert: true,
  depth: 3,

  # TLS protocol settings
  versions: [:"tlsv1.2", :"tlsv1.3"],
  honor_cipher_order: true,
  secure_renegotiate: true,
  reuse_sessions: true,

  # Advanced options
  alpn_advertised_protocols: ["h2", "http/1.1"],
  alpn_preferred_protocols: ["h2", "http/1.1"],
  log_level: :notice
```

### SSL Listen vs Handshake Options

The library distinguishes between SSL options used for socket listening and those used during SSL handshake:

**SSL Listen Options** (used when creating the SSL listening socket):
- Certificate and key files (`certfile`, `keyfile`, `cacertfile`, `certchain`)
- Certificate password (`password`)
- TLS versions (`versions`)
- Logging level (`log_level`)

**SSL Handshake Options** (used during client SSL handshake):
- Verification settings (`verify`, `fail_if_no_peer_cert`, `depth`)
- Connection settings (`honor_cipher_order`, `secure_renegotiate`, `reuse_sessions`)
- Cipher configuration (`ciphers`)
- CA certificate for verification (`cacertfile`)

This separation ensures that certificate-related options are properly configured during socket creation, while connection and verification options are applied during the handshake phase.

## Certificate Path Resolution

The library supports multiple ways to specify certificate paths:

1. **Absolute paths**: `/etc/ssl/certs/server.pem`
2. **Relative paths**: The library will try to resolve relative paths in the following order:
   - Relative to current working directory
   - Relative to the application's `priv` directory
3. **Environment variable expansion**: Paths can use environment variables

## Runtime Configuration

You can also pass SSL options when starting the server:

```elixir
{:ok, server} = Membrane.RTMPServer.start_link(
  port: 1935,
  use_ssl?: true,
  ssl_options: [
    certfile: "/path/to/your/certificate.pem",
    keyfile: "/path/to/your/private_key.pem",
    verify: :verify_none,
    fail_if_no_peer_cert: false,
    versions: [:"tlsv1.2", :"tlsv1.3"],
    log_level: :info
  ],
  handle_new_client: fn client_ref, app, stream_key ->
    # Your client handler logic here
    MyApp.ClientHandler
  end
)
```

## Configuration Debugging

To debug your SSL configuration, you can get a summary of all configuration sources:

```elixir
# Get configuration summary
summary = Membrane.RTMPServer.Config.get_ssl_config_summary()

# This returns a map with:
# %{
#   defaults: [...],     # Default SSL options
#   app_config: [...],   # From application config
#   runtime: [...],      # Runtime options passed to the function
#   final: [...]         # Final merged configuration
# }

IO.inspect(summary, label: "SSL Configuration Summary")
```

## Priority Order

SSL options are applied in the following priority order (highest to lowest):

1. **Runtime options** passed to `start_link/1`
2. **Application configuration** (`:membrane_rtmp_plugin, :ssl`)
3. **Default SSL options**

Higher priority sources will override settings from lower priority sources.

## Generating Self-Signed Certificates for Testing

For testing purposes, you can generate self-signed certificates:

```bash
# Generate private key
openssl genrsa -out private_key.pem 2048

# Generate certificate
openssl req -new -x509 -key private_key.pem -out certificate.pem -days 365 \
  -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost"
```

## SSL Options Reference

### Certificate Configuration
- `certfile`: Path to the certificate file (PEM format)
- `keyfile`: Path to the private key file (PEM format)
- `cacertfile`: Path to CA certificate bundle (for client verification)
- `certchain`: Path to certificate chain file (PEM format)
- `password`: Password for encrypted certificate files

### Verification Settings
- `verify`: `:verify_none` or `:verify_peer`
- `fail_if_no_peer_cert`: Boolean, whether to fail if client doesn't provide certificate
- `depth`: Maximum certificate chain depth for verification

### Protocol Settings
- `versions`: List of supported TLS versions (e.g., `[:"tlsv1.2", :"tlsv1.3"]`)
- `honor_cipher_order`: Boolean, whether to honor server cipher order
- `secure_renegotiate`: Boolean, whether to use secure renegotiation
- `reuse_sessions`: Boolean, whether to reuse SSL sessions

### Advanced Options
- `ciphers`: List of allowed cipher suites
- `alpn_advertised_protocols`: List of ALPN protocols to advertise
- `alpn_preferred_protocols`: List of preferred ALPN protocols
- `sni_hosts`: SNI host configuration (for multi-domain certificates)
- `log_level`: SSL logging level (`:none`, `:error`, `:warning`, `:notice`, `:info`, `:debug`, `:all`)

## Common Configuration Examples

### Production Configuration (High Security)
```elixir
config :membrane_rtmp_plugin, :ssl,
  certfile: "/etc/ssl/certs/server.pem",
  keyfile: "/etc/ssl/private/server.key",
  cacertfile: "/etc/ssl/certs/ca-bundle.pem",
  verify: :verify_peer,
  fail_if_no_peer_cert: true,
  depth: 5,
  versions: [:"tlsv1.2", :"tlsv1.3"],
  honor_cipher_order: true,
  secure_renegotiate: true,
  reuse_sessions: true,
  log_level: :warning
```

### Development Configuration (Self-Signed)
```elixir
config :membrane_rtmp_plugin, :ssl,
  certfile: "priv/ssl/dev_cert.pem",
  keyfile: "priv/ssl/dev_key.pem",
  verify: :verify_none,
  fail_if_no_peer_cert: false,
  versions: [:"tlsv1.2", :"tlsv1.3"],
  log_level: :info
```

### Testing Configuration
```elixir
config :membrane_rtmp_plugin, :ssl,
  certfile: "test/fixtures/ssl/test_cert.pem",
  keyfile: "test/fixtures/ssl/test_key.pem",
  verify: :verify_none,
  fail_if_no_peer_cert: false,
  log_level: :debug
```

## SSL Requirements

When enabling SSL (`use_ssl?: true`), the following are **required**:

1. **Certificate file** (`certfile`): Path to your SSL certificate in PEM format
2. **Private key file** (`keyfile`): Path to your SSL private key in PEM format

Without these, the SSL listener will fail to start with a helpful error message.

## Quick Start

To quickly get started with SSL, follow these steps:

1. Obtain or generate your SSL certificate and private key files.
2. Place them in a secure directory on your server.
3. Update your Membrane RTMP configuration to include the paths to these files.
4. Set `use_ssl?: true` when starting your RTMP server.
5. Optionally, configure advanced SSL options as needed.
