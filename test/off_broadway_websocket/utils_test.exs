defmodule OffBroadwayWebSocket.UtilsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias OffBroadwayWebSocket.Utils

  @max_runs 100

  describe "on_demand/4" do
    property "pops n items from the queue if demand is met" do
      check all(
              size <- integer(1..1000),
              min_demand <- integer(0..(size - 1)),
              demand <- integer(0..(size - 1)),
              xs <- list_of(integer(), length: size),
              max_runs: @max_runs
            ) do
        queue = :queue.from_list(xs)

        {count, ys, _} = Utils.on_demand(queue, min_demand, size, demand)

        assert {count, ys} == {demand, Enum.take(xs, demand)}
      end
    end

    property "returns empty list and zero counter when demand is not met" do
      check all(
              min_demand <- integer(1..1000),
              size <- integer(0..(min_demand - 1)),
              demand <- non_negative_integer(),
              xs <- list_of(integer()),
              max_runs: @max_runs
            ) do
        queue = :queue.from_list(xs)

        assert Utils.on_demand(queue, min_demand, size, demand) == {0, [], queue}
      end
    end
  end

  describe "pop_n/2" do
    property "retrieves n items from the queue" do
      check all(
              m <- non_negative_integer(),
              n <- integer(0..m),
              xs <- list_of(integer(), length: m),
              max_runs: @max_runs
            ) do
        {_, ys, _} = Utils.pop_n(:queue.from_list(xs), n)

        assert Enum.take(xs, n) == ys
      end
    end
  end
end
