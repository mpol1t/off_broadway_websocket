# Getting Started

`off_broadway_websocket` provides a Broadway producer backed by `gun` for websocket APIs.

Use it when you need:

- back-pressure aware websocket ingestion through Broadway
- reconnect and retry handling
- optional post-upgrade subscribe/bootstrap frames
- optional session-aware inbound frame handling

## Installation

Add the dependency to your `mix.exs`:

```elixir
def deps do
  [
    {:off_broadway_websocket, "~> 1.2.1"}
  ]
end
```

Fetch dependencies:

```bash
mix deps.get
```

## Minimal Broadway setup

```elixir
defmodule MyApp.Broadway do
  use Broadway

  alias Broadway.Message
  alias Broadway.NoopAcknowledger

  def start_link(_opts) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {
          OffBroadwayWebSocket.Producer,
          url: "wss://example.com",
          path: "/stream",
          telemetry_id: :example_ws
        },
        transformer: {__MODULE__, :transform, []},
        concurrency: 1
      ],
      processors: [
        default: [min_demand: 0, max_demand: 100, concurrency: 4]
      ]
    )
  end

  def handle_message(_stage, message, _context), do: message

  def transform(payload, _opts) do
    %Message{
      data: payload,
      acknowledger: NoopAcknowledger.init()
    }
  end
end
```

## Next steps

- See [Configuration](configuration.md) for producer options.
- See [Auth Refresh and Handshake Failures](auth_refresh_and_handshake_failures.md) for auth header rotation.
- See [On Upgrade Bootstrap](on_upgrade_bootstrap.md) for subscription-style APIs.
- See [Frame Handler](frame_handler.md) for session-aware protocols such as channel-id multiplexing.
