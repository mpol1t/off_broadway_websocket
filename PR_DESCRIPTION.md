# Release OffBroadwayWebSocket 1.2.0

## Summary

Prepare `off_broadway_websocket` for the `1.2.0` release.

This release packages the websocket bootstrap and session-aware frame handling work that was validated while integrating Kraken and Bitfinex public producers. It also brings the library documentation up to release quality so the new behavior is documented in HexDocs rather than only implied by tests and downstream usage.

## What Changed

- bumped the library version to `1.2.0`
- added HexDocs configuration in `mix.exs`
- added `CHANGELOG.md`
- rewrote `README.md` as a cleaner HexDocs landing page
- added focused guides for:
  - getting started
  - configuration
  - on-upgrade bootstrap
  - frame handler usage
  - retry and liveness semantics
  - telemetry

## Release Surface

This release documents and ships the following transport capabilities:

- `:on_upgrade`
  - send outbound websocket frames immediately after upgrade and before the connection is considered ready
- `:frame_handler`
  - process normalized inbound frames with connection-local state
- `:frame_handler_state`
  - provide explicit initial state that resets on reconnect
- reconnect/backoff handling for immediate bootstrap failures
- liveness refresh for skipped frames handled by the frame handler

Existing users remain backward compatible unless they opt into the new callback options.

## Why This Matters

The library now supports the two websocket integration patterns that were missing from the original producer:

- subscription-style protocols that require frames to be sent after upgrade
- session-aware protocols that require connection-local correlation before data can be emitted downstream

That makes the producer usable for exchanges like Kraken and Bitfinex without pushing protocol-specific state into downstream Broadway stages.

## Verification

- `make test-service-docker SERVICE=off_broadway_websocket`
  - `4 properties, 47 tests, 0 failures`

## Notes

- I also attempted a containerized `mix docs` build, but Hex package resolution in the container environment failed before docs generation completed.
- No push was performed.
