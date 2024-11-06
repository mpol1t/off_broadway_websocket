# OffBroadwayWebSocket

An Elixir library that provides a **Broadway** producer for handling WebSocket connections using the **gun** library. It supports reconnecting, ping/pong timeout monitoring, and demand-based message dispatching in an Off-Broadway setup.

## Features

- Automatically manages WebSocket connections.
- Reconnects upon disconnection, with configurable retry intervals.
- Monitors WebSocket connections with ping/pong messages and triggers reconnects on timeout.
- Integrates seamlessly with **Broadway** for demand-driven message processing.

## Installation

Add `off_broadway_websocket` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:off_broadway_websocket, "~> 0.0.2"}
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
          reconnect_delay: 5_000,
          ws_timeout: 15_000,
          reconnect_initial_delay: 1_000,
          reconnect_max_delay: 60_000,
          ws_opts: %{keepalive: 10_000, silence_pings: false},
          http_opts: %{version: :"HTTP/1.1"}
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
    case decode_message(raw_message) do
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

  defp decode_message(message) when is_binary(message) do
    Jason.decode(message)
  end

  defp decode_message(other) do
    {:error, {:unsupported_message_format, other}}
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
- **reconnect_delay**: Initial delay (in milliseconds) before attempting to reconnect after disconnection.
- **ws_timeout**: Time in milliseconds to wait for a pong response before assuming the connection is lost.
- **reconnect_initial_delay**: Initial delay for reconnection attempts.
- **reconnect_max_delay**: Maximum delay between reconnection attempts.
- **ws_opts**: WebSocket-specific options passed to the **gun 2.1** library, such as `keepalive` and `silence_pings`.
- **http_opts**: HTTP-specific options also compatible with **gun 2.1**, including version or custom headers.

Complete list of options accepted by `http_opts` and `ws_opts` is available [here](https://ninenines.eu/docs/en/gun/2.1/manual/gun/).

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
