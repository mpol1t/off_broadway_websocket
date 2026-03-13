# Changelog

All notable changes to this project are documented in this file.

The format is based on Keep a Changelog, and this project follows Semantic Versioning.

## [1.2.0] - 2026-03-13

### Added

- Added `:on_upgrade` to send outbound websocket frames immediately after upgrade and before the connection is considered ready.
- Added `:frame_handler` and `:frame_handler_state` for session-aware inbound websocket protocols.
- Added reconnect-time reset of connection-local frame-handler state.
- Added HexDocs guide structure for configuration, bootstrap hooks, frame handlers, retry/liveness, and telemetry.

### Changed

- Treat immediate `on_upgrade` callback failures and immediate `:gun.ws_send/3` failures as bootstrap failures that follow reconnect/backoff.
- Allow skipped inbound frames to refresh liveness when using a `:frame_handler`.
- Delay connection-success telemetry and ready-state transition until bootstrap frames have been sent successfully.

### Tests

- Expanded producer and state coverage for bootstrap success/failure, frame-handler emit/skip/error paths, and reconnect state reset.

## [1.1.1] - 2025-03-05

### Changed

- Released the current `1.1.x` line after the signal-handling improvements from `1.1.0`.

## [1.1.0] - 2025-03-02

### Added

- Added a dedicated telemetry module and expanded connection telemetry coverage.
- Added handling for missing `:gun_ws` signal clauses.

### Changed

- Improved connection defaults and state enforcement.
- Refactored producer and state handling around websocket lifecycle and retry behavior.
- Improved project documentation.

## [1.0.2] - 2024-10-29

### Changed

- Released the `1.0.x` line before the later signal-handling and telemetry refactor work.
