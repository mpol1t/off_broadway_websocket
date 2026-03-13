# On Upgrade Bootstrap

Some websocket APIs require outbound subscribe or bootstrap frames after the websocket upgrade completes.

Use `:on_upgrade` for that case.

## Contract

Pass an MFA:

```elixir
on_upgrade: {MyApp.Subscriptions, :bootstrap_frames, [args]}
```

The callback must return one of:

- `{:ok, []}`
- `{:ok, [{:text | :binary, iodata()}, ...]}`
- `{:error, reason}`

## Semantics

- the callback runs after websocket upgrade
- returned frames are sent in order with `:gun.ws_send/3`
- the producer is not considered ready until bootstrap succeeds
- connection-success telemetry is emitted only after bootstrap succeeds

## Failure behavior

These are treated as bootstrap failures:

- callback returns `{:error, reason}`
- callback returns an invalid result
- immediate `:gun.ws_send/3` failure for any returned frame
- callback raises

Bootstrap failure follows the same reconnect/backoff path as connection failure.

## Typical use cases

- Kraken-style post-upgrade subscribe messages
- authentication or session-init frames
- initial channel registration before downstream processing starts
