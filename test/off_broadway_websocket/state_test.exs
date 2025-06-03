defmodule OffBroadwayWebSocket.StateTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias OffBroadwayWebSocket.State

  @max_runs 100

  describe "new/1" do
    property "creates a State struct with specified values and defaults" do
      check all(
              min_demand    <- non_negative_integer(),
              max_demand    <- non_negative_integer(),
              url           <- string(:ascii, min_length: 1, max_length: 10),
              path          <- string(:ascii, min_length: 1, max_length: 10),
              gun_opts      <- map_of(string(:ascii, min_length: 1, max_length: 5), integer()),
              ws_timeout    <- non_negative_integer(),
              await_timeout <- non_negative_integer(),
              headers       <-
                list_of({string(:ascii, min_length: 1, max_length: 5), string(:ascii, min_length: 1, max_length: 5)}),
              telemetry_id  <- atom(:alphanumeric),
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
            url:           url,
            path:          path,
            gun_opts:      gun_opts,
            ws_timeout:    ws_timeout,
            await_timeout: await_timeout,
            headers:       headers,
            telemetry_id:  telemetry_id
          )

        assert %State{
                 min_demand:    ^min_demand,
                 max_demand:    ^max_demand,
                 url:           ^url,
                 path:          ^path,
                 gun_opts:      ^gun_opts,
                 ws_timeout:    ^ws_timeout,
                 await_timeout: ^await_timeout,
                 headers:       ^headers,
                 telemetry_id:  ^telemetry_id
               } = state
      end
    end

    test "uses default values for unspecified fields" do
      state = State.new(url: "ws://example.com", path: "/socket")

      assert state.min_demand         == 10
      assert state.max_demand         == 100
      assert state.await_timeout      == 10_000
      assert state.gun_opts           == %{}
      assert state.ws_timeout         == nil
      assert state.headers            == []
      assert state.telemetry_id       == :websocket_producer
      assert state.message_queue      == :queue.new()
      assert state.ws_retry_opts      == State.default_ws_retry_opts()
      assert state.ws_init_retry_opts == State.default_ws_retry_opts()
    end
  end

  describe "default_ws_retry_opts/0" do
    test "returns the correct default map" do
      opts = State.default_ws_retry_opts()

      assert is_map(opts)

      assert Enum.sort(Map.keys(opts)) == [:delay, :max_retries, :retries_left]
      assert opts.max_retries  == 5
      assert opts.retries_left == 5
      assert opts.delay        == 10_000
    end
  end

  describe "default_ws_retry_fun/1" do
    test "when retries_left > 0 decrements retries_left and returns new state" do
      initial = %{max_retries: 3, retries_left: 3, delay: 2_000}
      result = State.default_ws_retry_fun(initial)

      assert result.retries_left == 2
      assert result.delay        == initial.delay
    end

    test "when retries_left == 0 returns zero retries and unchanged state" do
      initial = %{max_retries: 3, retries_left: 0, delay: 2_000}
      result = State.default_ws_retry_fun(initial)

      assert result.retries_left == 0
      assert result.delay        == initial.delay
    end

    property "eventually sets retries_left to zero and preserves other keys" do
      extra_key_gen =
        atom(:alphanumeric)
        |> filter(&(&1 not in [:max_retries, :retries_left, :delay]))

      check all(
              max_retries  <- integer(0..10),
              delay        <- positive_integer(),
              retries_left <- integer(0..max_retries),
              extra        <- map_of(extra_key_gen, integer()),
              max_runs: @max_runs
            ) do
        opts =
          %{max_retries: max_retries, retries_left: retries_left, delay: delay}
          |> Map.merge(extra)

        final_opts =
          Enum.reduce(1..(retries_left + 1), opts, fn _, acc ->
            State.default_ws_retry_fun(acc)
          end)

        assert final_opts.retries_left == 0
        assert final_opts.delay == delay

        for {k, v} <- extra do
          assert Map.get(final_opts, k) == v
        end
      end
    end
  end
end
