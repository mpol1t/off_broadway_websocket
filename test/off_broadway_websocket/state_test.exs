defmodule OffBroadwayWebSocket.StateTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias OffBroadwayWebSocket.State

  @max_runs 100

  describe "new/1" do
    property "creates a State struct with specified values and defaults" do
      check all(
              min_demand <- non_negative_integer(),
              max_demand <- non_negative_integer(),
              url <- string(:ascii, min_length: 1, max_length: 10),
              path <- string(:ascii, min_length: 1, max_length: 10),
              ws_opts <- map_of(string(:ascii, min_length: 1, max_length: 10), integer()),
              http_opts <- map_of(string(:ascii, min_length: 1, max_length: 10), integer()),
              ws_timeout <- non_negative_integer(),
              await_timeout <- non_negative_integer(),
              connect_timeout <- non_negative_integer(),
              event_producer_id <- atom(:alphanumeric),
              max_runs: @max_runs
            ) do
        state =
          State.new(
            broadway: [
              processors: [
                default: [
                  min_demand: min_demand,
                  max_demand: max_demand
                ]
              ]
            ],
            url: url,
            path: path,
            ws_opts: ws_opts,
            http_opts: http_opts,
            ws_timeout: ws_timeout,
            await_timeout: await_timeout,
            connect_timeout: connect_timeout,
            event_producer_id: event_producer_id
          )

        assert %State{
                 min_demand: ^min_demand,
                 max_demand: ^max_demand,
                 url: ^url,
                 path: ^path,
                 ws_opts: ^ws_opts,
                 http_opts: ^http_opts,
                 ws_timeout: ^ws_timeout,
                 await_timeout: ^await_timeout,
                 connect_timeout: ^connect_timeout,
                 event_producer_id: ^event_producer_id
               } = state
      end
    end

    test "uses default values for unspecified fields" do
      state = State.new([])

      assert state.min_demand == 10
      assert state.max_demand == 100
      assert state.await_timeout == 10_000
      assert state.connect_timeout == 60_000
      assert state.message_queue == :queue.new()
      assert state.event_producer_id == :websocket_producer
    end
  end
end
