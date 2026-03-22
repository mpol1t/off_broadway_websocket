# Auth Refresh and Handshake Failures

Some websocket APIs require short-lived auth headers.
`off_broadway_websocket` supports this with `:headers_fn`.

## Refreshing headers on each connect

```elixir
producer: [
  module: {
    OffBroadwayWebSocket.Producer,
    url: "wss://api.exchange.example",
    path: "/v1/stream",
    headers_fn: fn ->
      token = MyApp.Auth.refresh_ws_token!()
      [{"authorization", "Bearer " <> token}]
    end
  }
]
```

`headers_fn` is called before each connection attempt, including reconnects.

## Return contract

`headers_fn` must return one of:

- header list: `[{binary(), binary()}]`
- `{:ok, [{binary(), binary()}]}`
- `{:error, reason}`

If it raises or returns an invalid value, the connect attempt fails with a typed error and standard retry/backoff behavior continues.

## Handshake failures

When the websocket upgrade returns an HTTP status >= 400, the producer stops with:

- `{:handshake_failure, {status, headers}}`

Both `:nofin` and `:fin` response variants are handled.

## Operational guidance

- Keep `headers_fn` fast and side-effect free when possible.
- Add telemetry around your token refresh function.
- Prefer deterministic refresh errors so retry behavior is predictable.
