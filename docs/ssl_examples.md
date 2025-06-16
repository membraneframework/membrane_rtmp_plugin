# SSL Configuration Examples for Membrane RTMP Plugin

This directory contains example SSL configurations for different environments.

## Quick Start

1. **Development (Self-Signed Certificates)**
   ```elixir
   # config/dev.exs
   import Config

   config :membrane_rtmp_plugin, :ssl,
     certfile: "priv/ssl/dev_cert.pem",
     keyfile: "priv/ssl/dev_key.pem",
     verify: :verify_none,
     fail_if_no_peer_cert: false,
     log_level: :info
   ```

2. **Production (CA-Signed Certificates)**
   ```elixir
   # config/prod.exs
   import Config

   config :membrane_rtmp_plugin, :ssl,
     certfile: "/etc/ssl/certs/server.pem",
     keyfile: "/etc/ssl/private/server.key",
     cacertfile: "/etc/ssl/certs/ca-bundle.pem",
     verify: :verify_peer,
     fail_if_no_peer_cert: true,
     depth: 5,
     versions: [:"tlsv1.2", :"tlsv1.3"],
     honor_cipher_order: true,
     log_level: :warning
   ```

3. **Using Environment Variables**
   ```bash
   export RTMP_SSL_CERTFILE="/path/to/cert.pem"
   export RTMP_SSL_KEYFILE="/path/to/key.pem"
   export RTMP_SSL_CACERTFILE="/path/to/ca-bundle.pem"
   ```

4. **Runtime Configuration**
   ```elixir
   {:ok, server} = Membrane.RTMPServer.start_link(
     port: 1935,
     use_ssl?: true,
     ssl_options: [
       certfile: "/runtime/cert.pem",
       keyfile: "/runtime/key.pem",
       verify: :verify_none
     ],
     handle_new_client: &MyApp.handle_client/3
   )
   ```

## Configuration Priority

SSL options are applied in this priority order (highest to lowest):
1. Runtime options (passed to `start_link/1`)
2. Application configuration (`:membrane_rtmp_plugin, :ssl`)
3. Environment variables
4. Default SSL options

## Debugging Configuration

To debug your SSL configuration, use the configuration summary:

```elixir
summary = Membrane.RTMPServer.Config.get_ssl_config_summary()
IO.inspect(summary, label: "SSL Config Summary")
```

## Certificate Path Resolution

The library automatically:
- Expands relative paths to absolute paths
- Tries to resolve relative paths in the application's `priv` directory
- Validates certificate file existence (when enabled)
