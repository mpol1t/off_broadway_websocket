# Telemetry

Telemetry events are emitted under:

```elixir
[:<telemetry_id>, :connection, <event>]
```

## Events

- `:success`
- `:failure`
- `:disconnected`
- `:timeout`
- `:status`

## Measurements

- `:success` -> `%{count: 1}`
- `:failure` -> `%{count: 1}`
- `:disconnected` -> `%{count: 1}`
- `:timeout` -> `%{count: 1}`
- `:status` -> `%{value: 0 | 1}`

## Metadata

- `:success` includes `%{url: String.t()}`
- `:failure` includes `%{reason: term()}`
- `:disconnected` includes `%{reason: term()}`

## Notes

- connection-success telemetry is emitted only after websocket upgrade and successful `:on_upgrade` bootstrap, if configured
- frame-handler failures are reported through the connection failure path

## Example

```elixir
:telemetry.attach(
  "off-broadway-websocket-success",
  [:websocket_producer, :connection, :success],
  fn event, measurements, metadata, _config ->
    IO.inspect({event, measurements, metadata}, label: "telemetry")
  end,
  nil
)
```
