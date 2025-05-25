[![codecov](https://codecov.io/gh/mpol1t/off_broadway_websocket/graph/badge.svg?token=ZDf9PrffNJ)](https://codecov.io/gh/mpol1t/off_broadway_websocket)
[![Hex.pm Version](https://img.shields.io/hexpm/v/off_broadway_websocket)](https://hex.pm/packages/off_broadway_websocket)
[![License](https://img.shields.io/github/license/mpol1t/off_broadway_websocket.svg)](https://github.com/mpol1t/off_broadway_websocket/blob/main/LICENSE)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/off_broadway_websocket)
[![Build Status](https://github.com/mpol1t/off_broadway_websocket/actions/workflows/elixir.yml/badge.svg)](https://github.com/mpol1t/off_broadway_websocket/actions)
[![Elixir Version](https://img.shields.io/badge/elixir-~%3E%201.16-purple.svg)](https://elixir-lang.org/)

# OffBroadwayWebSocket

An Elixir library providing a **Broadway** producer for resilient WebSocket connections using **gun**.  
Supports unified `gun_opts`, idle‐timeout detection (ping/pong & data frames), demand‐based dispatch, and custom retry strategies.

---

## Installation


Add to your `mix.exs`:
```elixir
def deps do
  [
    {:off_broadway_websocket, "~> 1.0.0"}
  ]
end
```
Fetch & compile:


```bash
mix deps.get
mix deps.compile
```
---

## Quickstart

```elixir
defmodule MyApp.Broadway do
  use Broadway
  
  require Logger
  
  alias Broadway.Message
  alias Broadway.NoopAcknowledger

  def start_link(_args) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {
          OffBroadwayWebSocket.Producer,
          # Your WebSocket endpoint:
          url: "wss://example.com:443",
          path: "/stream/updates",

          # Idle timeout (ms) for no ping/data before reconnect:
          ws_timeout: 15_000,
          # How long to wait (ms) for Gun to come up:
          await_timeout: 8_000,

          # Retry configuration – must include at least :retries_left and :delay:
          ws_retry_opts: %{
            max_retries:     5,
            retries_left:    5,
            delay:           1_000,   # initial backoff (ms)
            max_delay:       30_000,  # cap for backoff (ms)
            backoff_factor:  2,       # exponential factor
            jitter_fraction: 0.1      # ±10% random jitter
          },
          ws_retry_fun: &MyApp.Backoff.exponential_backoff_with_jitter/1,

          # Gun options (TCP/TLS, HTTP, WS):
          gun_opts: %{
            connect_timeout: 5_000,      # TCP/TLS handshake timeout
            protocols:       [:http],     # application protocols
            transport:       :tls,        # :tcp or :tls

            tls_opts: [
              verify:         :verify_peer,
              cacertfile:     CAStore.file_path(),
              depth:          10,
              reuse_sessions: false,
              verify_fun:     {
                &:ssl_verify_hostname.verify_fun/3,
                [check_hostname: String.to_charlist("example.com")]
              }
            ],

            ws_opts: %{
              keepalive:     10_000,  # send ping if silent
              silence_pings: false
            },

            http_opts: %{
              version:       :"HTTP/1.1"
            }
          },

          # Prefix for telemetry events:
          telemetry_id: :custom_telemetry,
          # Optional headers
          headers: [  
            {"X-ABC-APIKEY", "api-key"},
            {"X-ABC-PAYLOAD", %{}},
            {"X-ABC-SIGNATURE", "signature"}
          ],
        },
        transformer: {__MODULE__, :transform, []},
        concurrency: 1
      ],
      processors: [
        default: [min_demand: 0, max_demand: 100, concurrency: 8]
      ],
      context: []
    )
  end

  @impl true
  def handle_message(_stage, %Message{data: raw} = msg, _ctx) do
    case Jason.decode(raw) do
      {:ok, data} ->
        Logger.debug(fn -> "Data: #{inspect(data)}" end)
        msg

      {:error, err} ->
        Logger.error("Decode error: #{inspect(err)}")
        Message.failed(msg, err)
    end
  end

  def transform(event, _opts) do
    %Broadway.Message{
      data:        event,
      acknowledger: NoopAcknowledger.init()
    }
  end
end
```

---

## Configuration Options

When calling `OffBroadwayWebSocket.Producer`, you may pass:

- **`:url`** (_string_, required) — WebSocket base URL.
- **`:path`** (_string_, required) — Upgrade path and querystring.
- **`:ws_timeout`** (_ms_, optional) — Idle timeout for no ping/data.
- **`:await_timeout`** (_ms_, optional) — Timeout for `:gun.await_up/2`.
- **`:headers`** (_list_, optional) — HTTP headers for WS upgrade.
- **`:min_demand`** / **`:max_demand`** (_integer_) — Broadway backpressure.
- **`:telemetry_id`** (_atom_) — Prefix for telemetry events.
- **`:gun_opts`** (_map_) — All options forwarded to `:gun.open/3` and friends.
- **`:ws_retry_opts`** (_map_) — Your initial retry state; must include:
    - `:retries_left`, `:delay` (ms).
    - Extra keys (e.g. `:backoff_factor`, `:jitter_fraction`) are carried through.
- **`:ws_retry_fun`** (_function_) — A `(retry_opts() -> retry_opts())` function.
  After each failed connect, the returned map’s `:delay` is used and stored as the next call’s input. After successful
  reconnection, `:ws_retry_opts` are reset to initial value.

---

## Default Configuration

Out of the box, `OffBroadwayWebSocket.Producer` uses these defaults:

| Option             | Default                            | Description                                 |
|--------------------|------------------------------------|---------------------------------------------|
| `:url`             | **—**                              | WebSocket URL (required)                    |
| `:path`            | **—**                              | WebSocket path (required)                   |
| `:ws_timeout`      | `nil`                              | Idle timeout (ms) for ping/data             |
| `:await_timeout`   | `10_000`                           | `gun.await_up/2` timeout (ms)               |
| `:headers`         | `[]`                               | Upgrade HTTP headers                        |
| `:min_demand`      | `10`                               | Broadway `min_demand`                       |
| `:max_demand`      | `100`                              | Broadway `max_demand`                       |
| `:telemetry_id`    | `:websocket_producer`              | Prefix for telemetry events                 |
| `:gun_opts`        | `%{}`                              | Direct options to `:gun.open/3`, etc.       |
| `:ws_retry_opts`   | see _Default `ws_retry_opts`_      | Initial retry state                         |
| `:ws_retry_fun`    | `&OffBroadwayWebSocket.State.default_ws_retry_fun/1`    | Backoff function contract                   |

### Default Backoff Function

By default, a constant backoff function is used with the config shown below:

```elixir
%{
  max_retries:  5,     # total retry attempts
  retries_left: 5,     # decremented on each failure
  delay:        10_000 # constant delay in ms between retries
}
```
---

## Telemetry Events

Fired under `[:<telemetry_id>, :connection, <event>]`:

| Event           | Measurements    | Metadata          | Description                       |
|-----------------|-----------------|-------------------|-----------------------------------|
| `:success`      | `%{count: 1}`   | `%{url: String}`  | Handshake completed               |
| `:failure`      | `%{count: 1}`   | `%{reason: term}` | Connect or upgrade failed         |
| `:disconnected` | `%{count: 1}`   | `%{reason: term}` | Underlying TCP connection dropped |
| `:timeout`      | `%{count: 1}`   | `%{}`             | Idle ping/data timeout            |
| `:status`       | `%{value: 0|1}` | `%{}`             | `0`=down, `1`=up                  |

Attach as usual:

```elixir
:telemetry.attach(
  "log-connection-success",
  [:websocket_producer, :connection, :success],
  fn event_name, measurements, metadata, _config ->
    IO.inspect({event_name, measurements, metadata}, label: "Telemetry Event")
  end,
  nil
)
```

---

## Running Tests

```bash
mix test
```

---

## Dialyzer

```bash
mix dialyzer --plt
mix dialyzer
```

---

## Contributing

PRs and issues welcome! Please follow Elixir conventions and include tests.

---

## License

Apache License 2.0 © 2025  