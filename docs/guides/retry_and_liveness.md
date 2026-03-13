# Retry and Liveness

The producer manages websocket lifecycle in two dimensions:

- retry and reconnect
- liveness tracking

## Reconnect and retry

Connection attempts are controlled by:

- `:ws_retry_opts`
- `:ws_retry_fun`

After a failed connect or bootstrap failure:

- `:ws_retry_fun` is called with the current retry state
- the returned `:delay` is used before the next attempt
- the updated retry state is stored for the next failure

After successful reconnect:

- retry state resets to the initial `:ws_retry_opts`
- `frame_handler_state` also resets to its initial baseline

## Liveness

Liveness is refreshed by:

- inbound data payloads
- inbound pong frames
- `{:skip, new_state}` frame-handler results

The producer checks inactivity with `:ws_timeout`.

If the websocket is idle beyond that timeout, the producer treats it as a timeout failure and reconnects.

## Important consequence

If your protocol emits heartbeats or acknowledgements that should not be sent downstream, handle them with `{:skip, new_state}` rather than dropping them outside the frame handler. That keeps the connection healthy without polluting Broadway messages.
