# Configuration

`OffBroadwayWebSocket.Producer` accepts these primary options.

## Required

- `:url` - websocket base URL
- `:path` - request path and query string if needed

## Common optional settings

- `:ws_timeout` - idle timeout in milliseconds
- `:await_timeout` - timeout for `:gun.await_up/2`
- `:headers` - websocket upgrade headers
- `:telemetry_id` - prefix for telemetry events
- `:gun_opts` - options forwarded to `:gun`
- `:min_demand` / `:max_demand` - Broadway producer demand settings

## Retry behavior

- `:ws_retry_opts` - retry state map
- `:ws_retry_fun` - function used to compute the next retry state

The default retry state is:

```elixir
%{
  max_retries: 5,
  retries_left: 5,
  delay: 10_000
}
```

## Bootstrap and session hooks

- `:on_upgrade` - optional MFA run after websocket upgrade and before readiness
- `:frame_handler` - optional MFA run for normalized inbound data frames
- `:frame_handler_state` - initial connection-local state for `:frame_handler`

## `gun_opts`

Use `:gun_opts` to configure:

- transport (`:tcp` or `:tls`)
- TLS verification
- HTTP version
- websocket keepalive and ping behavior

Example:

```elixir
gun_opts: %{
  connect_timeout: 5_000,
  protocols: [:http],
  transport: :tls,
  tls_opts: [
    verify: :verify_peer,
    cacertfile: CAStore.file_path()
  ],
  ws_opts: %{
    keepalive: 10_000,
    silence_pings: false
  },
  http_opts: %{
    version: :"HTTP/1.1"
  }
}
```
