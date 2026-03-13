# Frame Handler

Use `:frame_handler` for session-aware websocket protocols where raw incoming frames are not directly suitable as Broadway payloads.

Typical examples:

- channel-id multiplexing
- subscription acknowledgements that must update connection-local state
- heartbeat frames that should be swallowed but still refresh liveness

## Contract

Pass an MFA and optional initial state:

```elixir
frame_handler: {MyApp.Transport, :handle_frame, []},
frame_handler_state: %{subscriptions: %{}}
```

The callback receives:

1. the normalized inbound data payload
2. the current connection-local handler state
3. any extra MFA arguments

It must return one of:

- `{:emit, [payload, ...], new_state}`
- `{:skip, new_state}`
- `{:error, reason, new_state}`

## Semantics

### `{:emit, payloads, new_state}`

- queues zero, one, or many payloads downstream
- updates the handler state
- refreshes liveness

### `{:skip, new_state}`

- emits nothing downstream
- updates the handler state
- still refreshes liveness

### `{:error, reason, new_state}`

- updates the handler state for the current failure path
- fails the current connection
- follows reconnect/backoff

## Reconnect behavior

`frame_handler_state` is connection-local and resets to its initial baseline on reconnect.

This is important for protocols where session identifiers such as channel ids become invalid after reconnect.
