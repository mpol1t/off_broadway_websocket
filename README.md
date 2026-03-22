[![codecov](https://codecov.io/gh/mpol1t/off_broadway_websocket/graph/badge.svg?token=ZDf9PrffNJ)](https://codecov.io/gh/mpol1t/off_broadway_websocket)
[![Hex.pm Version](https://img.shields.io/hexpm/v/off_broadway_websocket)](https://hex.pm/packages/off_broadway_websocket)
[![License](https://img.shields.io/github/license/mpol1t/off_broadway_websocket.svg)](https://github.com/mpol1t/off_broadway_websocket/blob/main/LICENSE)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/off_broadway_websocket)
[![Build Status](https://github.com/mpol1t/off_broadway_websocket/actions/workflows/elixir.yml/badge.svg)](https://github.com/mpol1t/off_broadway_websocket/actions)
[![Elixir Version](https://img.shields.io/badge/elixir-~%3E%201.16-purple.svg)](https://elixir-lang.org/)

# OffBroadwayWebSocket

An Elixir library providing an Off-Broadway producer for resilient WebSocket ingestion with `:gun`.

It is designed for exchange-style or session-oriented WebSocket feeds where a Broadway pipeline needs:

- demand-aware delivery
- reconnect and backoff handling
- ping/pong and idle-timeout monitoring
- optional post-upgrade bootstrap frames
- optional stateful inbound frame handling

## Documentation

HexDocs includes the API reference and focused guides:

- [Getting Started](docs/guides/getting_started.md)
- [Configuration](docs/guides/configuration.md)
- [Auth Refresh and Handshake Failures](docs/guides/auth_refresh_and_handshake_failures.md)
- [On-Upgrade Bootstrap](docs/guides/on_upgrade_bootstrap.md)
- [Frame Handler](docs/guides/frame_handler.md)
- [Retry and Liveness](docs/guides/retry_and_liveness.md)
- [Telemetry](docs/guides/telemetry.md)

## Installation

Add `off_broadway_websocket` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:off_broadway_websocket, "~> 1.2.1"}
  ]
end
```

Then fetch dependencies:

```bash
mix deps.get
```

## Quickstart

```elixir
defmodule MyApp.Broadway do
  use Broadway

  alias Broadway.Message
  alias Broadway.NoopAcknowledger

  def start_link(_args) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {
          OffBroadwayWebSocket.Producer,
          url: "wss://example.com:443",
          path: "/stream/trades",
          ws_timeout: 15_000,
          telemetry_id: :my_app_ws,
          gun_opts: %{
            transport: :tls,
            protocols: [:http],
            tls_opts: [
              verify: :verify_peer,
              cacertfile: CAStore.file_path(),
              verify_fun: {
                &:ssl_verify_hostname.verify_fun/3,
                [check_hostname: String.to_charlist("example.com")]
              }
            ],
            http_opts: %{version: :"HTTP/1.1"},
            ws_opts: %{keepalive: 10_000, silence_pings: false}
          },
          on_upgrade: {MyApp.WebSocket, :subscription_frames, [[]]},
          frame_handler: {MyApp.WebSocket, :handle_frame, []},
          frame_handler_state: %{subscriptions: %{}}
        },
        transformer: {__MODULE__, :transform, []},
        concurrency: 1
      ],
      processors: [default: [min_demand: 0, max_demand: 100, concurrency: 4]]
    )
  end

  def handle_message(_stage, %Message{data: payload} = message, _context) do
    message
    |> Map.put(:data, payload)
  end

  def transform(payload, _opts) do
    %Broadway.Message{
      data: payload,
      acknowledger: NoopAcknowledger.init()
    }
  end
end
```

## Core Concepts

### On-upgrade bootstrap

Use `:on_upgrade` when a websocket API requires subscribe or auth frames to be sent
immediately after upgrade and before the connection should be considered ready.

The callback must return one of:

- `{:ok, []}`
- `{:ok, [{:text | :binary, iodata()}, ...]}`
- `{:error, reason}`

Immediate callback failure or immediate `:gun.ws_send/3` failure is treated as a
bootstrap failure and follows the reconnect/backoff path.

### Stateful inbound frame handling

Use `:frame_handler` when raw websocket frames depend on connection-local session
state, for example subscription ids or channel mappings.

The callback receives a normalized inbound payload and the current handler state and
must return one of:

- `{:emit, [payload, ...], new_state}`
- `{:skip, new_state}`
- `{:error, reason, new_state}`

`frame_handler_state` resets to its initial value on reconnect.

## Configuration Overview

Required startup options:

- `:url`
- `:path`

Common optional startup options:

- `:headers`
- `:headers_fn`
- `:ws_timeout`
- `:await_timeout`
- `:telemetry_id`
- `:gun_opts`
- `:ws_retry_opts`
- `:ws_retry_fun`
- `:on_upgrade`
- `:frame_handler`
- `:frame_handler_state`

See [Configuration](docs/guides/configuration.md) for the full option contract and defaults.

Use [Auth Refresh and Handshake Failures](docs/guides/auth_refresh_and_handshake_failures.md)
for rotating websocket auth headers and troubleshooting failed upgrades.

## Telemetry

Connection telemetry is emitted under:

- `[:<telemetry_id>, :connection, :success]`
- `[:<telemetry_id>, :connection, :failure]`
- `[:<telemetry_id>, :connection, :disconnected]`
- `[:<telemetry_id>, :connection, :timeout]`
- `[:<telemetry_id>, :connection, :status]`

See [Telemetry](docs/guides/telemetry.md) for event shapes and usage examples.

## Boundary

`OffBroadwayWebSocket` owns:

- websocket connection lifecycle
- reconnect/backoff behavior
- idle-timeout and keepalive handling
- optional bootstrap frame dispatch
- optional connection-local inbound frame handling

Application code owns:

- payload decoding and validation
- domain-specific adaptation
- downstream routing and publishing
- session policy beyond the transport boundary

## Running Tests

```bash
mix test
```

## License

Apache License 2.0. See [LICENSE](LICENSE).
