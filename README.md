# OffBroadwayWebSocket

An Elixir library that provides a **Broadway** producer for handling WebSocket connections using the **gun** library. It supports ping/pong timeout monitoring, and demand-based message dispatching in an Off-Broadway setup.

## Features

- Manages WebSocket connections.
- Monitors WebSocket connections with ping/pong messages and triggers timeouts.
- Integrates seamlessly with **Broadway** for demand-driven message processing.

## Installation

Add `off_broadway_websocket` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:off_broadway_websocket, "~> 0.1.0"}
  ]
end
```

Run the following to fetch and compile the dependency:

```bash
mix deps.get
mix deps.compile
```

## Usage

### Basic Setup with **Broadway**

In your project, create a **Broadway** module to use the **OffBroadwayWebSocket.Producer** as the producer.

```elixir
defmodule MyApp.Broadway do
  use Broadway
  require Logger

  alias Broadway.Message

  def start_link(_args) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {
          OffBroadwayWebSocket.Producer,
          url: "wss://example.com",
          path: "/path_to_ws_endpoint",
          ws_timeout: 15_000,
          ws_opts: %{keepalive: 10_000, silence_pings: false},
          http_opts: %{version: :"HTTP/1.1"},
          telemetry_id: :custom_telemetry_id,
          headers: [  # Optional headers
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
      ]
    )
  end

  @impl true
  def handle_message(_processor, %Message{data: raw_message} = message, _context) do
    case Jason.decode(raw_message) do
      {:ok, %{"type" => "heartbeat"}} ->
        Logger.debug("Heartbeat message received.")
        message

      {:ok, data} ->
        Logger.info("Data received: #{inspect(data)}")
        message

      {:error, error} ->
        Logger.error("Failed to decode message: #{inspect(error)}")
        message
    end
  end

  def transform(event, _opts) do
    %Message{
      data: event,
      acknowledger: {__MODULE__, :ack_id, :ack_data}
    }
  end

  def ack(:ack_id, _successful, _failed) do
    :ok
  end
end
```

### Configuration Options

- **url**: The WebSocket URL.
- **path**: The WebSocket endpoint path.
- **ws_timeout**: Time in milliseconds to wait for a pong response before assuming the connection is lost.
- **ws_opts**: WebSocket-specific options passed to the **gun 2.1** library, such as `keepalive` and `silence_pings`.
- **http_opts**: HTTP-specific options also compatible with **gun 2.1**, including version or custom headers.
- **headers**: Optional headers to use when upgrading to WebSocket.
- **telemetry_id**: Optional custom identifier for telemetry events. Defaults to :websocket_producer.
Complete list of options accepted by `http_opts` and `ws_opts` is available [here](https://ninenines.eu/docs/en/gun/2.1/manual/gun/).

## Telemetry Events

**OffBroadwayWebSocket** emits telemetry events for key WebSocket operations. These events can be used for monitoring and integration with tools like Prometheus, Datadog, or other observability platforms.

### Event Table
| **Event Name**                                  | **Measurements** | **Metadata**          | **Description**                                           |
|-------------------------------------------------|------------------|-----------------------|-----------------------------------------------------------|
| `[:websocket_producer, :connection, :success]`  | `count: 1`       | `url: String`         | Emitted when a connection is successfully established.     |
| `[:websocket_producer, :connection, :failure]`  | `count: 1`       | `reason: term()`      | Emitted when a connection attempt fails.                  |
| `[:websocket_producer, :connection, :disconnected]` | `count: 1`       | `reason: term()`      | Emitted when the WebSocket connection is disconnected.     |
| `[:websocket_producer, :connection, :timeout]`  | `count: 1`       | (none)                | Emitted when a ping/pong timeout occurs.                  |
| `[:websocket_producer, :connection, :status]`   | `value: [0,1]`   | (none)                | Emitted to indicate the current WebSocket connection status (`0` = down, `1` = up). |

### Example Usage

You can attach custom handlers to these telemetry events for logging or monitoring purposes. Here's an example:

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

This allows you to customize behavior or integrate the events into observability tools.

### Running Tests

To run tests:

```bash
mix test
```

Ensure your WebSocket endpoint is reachable and configured properly for end-to-end tests.

### Running Dialyzer

For static analysis with Dialyzer, make sure PLTs are built:

```bash
mix dialyzer --plt
mix dialyzer
```

## Contributing

Feel free to open issues or submit PRs to enhance the functionality of **OffBroadwayWebSocket**. Contributions are welcome!

## License

This project is licensed under the Apache License, Version 2.0.
