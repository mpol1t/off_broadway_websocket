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
              reconnect_delay <- non_negative_integer(),
              reconnect_max_delay <- non_negative_integer(),
              reconnect_initial_delay <- non_negative_integer(),
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
            reconnect_delay: reconnect_delay,
            reconnect_max_delay: reconnect_max_delay,
            reconnect_initial_delay: reconnect_initial_delay
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
                 reconnect_delay: ^reconnect_delay,
                 reconnect_max_delay: ^reconnect_max_delay,
                 reconnect_initial_delay: ^reconnect_initial_delay
               } = state
      end
    end

    test "uses default values for unspecified fields" do
      state = State.new([])

      assert state.min_demand == 10
      assert state.max_demand == 100
      assert state.reconnect_delay == 5_000
      assert state.reconnect_initial_delay == 1_000
      assert state.reconnect_max_delay == 60_000
      assert state.await_timeout == 10_000
      assert state.connect_timeout == 60_000
      assert state.message_queue == :queue.new()
    end
  end

  describe "reset_reconnect_state/1" do
    property "resets reconnect attempts and delay" do
      check all(
              rec_initial <- non_negative_integer(),
              rec_delay <- non_negative_integer(),
              max_runs: @max_runs
            ) do
        initial_state = %State{
          reconnect_delay: rec_delay,
          reconnect_initial_delay: rec_initial,
          # simulate a non-zero reconnect_attempts
          reconnect_attempts: 5
        }

        reset_state = State.reset_reconnect_state(initial_state)

        assert reset_state.reconnect_attempts == 0
        assert reset_state.reconnect_delay == rec_initial
      end
    end

    test "sets reconnect_attempts to 0 and reconnect_delay to initial value when nil" do
      initial_state = %State{reconnect_initial_delay: 3_000}

      reset_state = State.reset_reconnect_state(initial_state)

      assert reset_state.reconnect_attempts == 0
      assert reset_state.reconnect_delay == 3_000
    end
  end
end
