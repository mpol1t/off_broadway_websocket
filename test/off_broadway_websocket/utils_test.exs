defmodule OffBroadwayWebSocket.UtilsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias OffBroadwayWebSocket.Utils

  @max_runs 100

  describe "on_demand/4" do
    property "pops `demand` items from the queue when demand is met" do
      check all(
              size <- integer(1..1000),
              min_demand <- integer(0..(size - 1)),
              demand <- integer(0..(size - 1)),
              xs <- list_of(integer(), length: size),
              max_runs: @max_runs
            ) do
        queue = :queue.from_list(xs)

        {count, ys, remaining_queue} = Utils.on_demand(queue, min_demand, size, demand)

        assert {count, ys} == {demand, Enum.take(xs, demand)}
        assert :queue.len(remaining_queue) == size - demand
      end
    end

    property "returns the entire queue and clears it when demand exceeds queue size" do
      check all(
              size <- integer(1..1000),
              min_demand <- integer(0..(size - 1)),
              xs <- list_of(integer(), length: size),
              max_runs: @max_runs
            ) do
        queue = :queue.from_list(xs)
        demand = size + 1

        {count, ys, remaining_queue} = Utils.on_demand(queue, min_demand, size, demand)

        assert {count, ys} == {size, xs}
        assert :queue.is_empty(remaining_queue)
      end
    end

    property "returns an empty list and zero count when demand is not met" do
      check all(
              min_demand <- integer(1..1000),
              size <- integer(0..(min_demand - 1)),
              demand <- non_negative_integer(),
              xs <- list_of(integer(), length: size),
              max_runs: @max_runs
            ) do
        queue = :queue.from_list(xs)

        assert Utils.on_demand(queue, min_demand, size, demand) == {0, [], queue}
      end
    end
  end

  describe "pop_n/2" do
    property "retrieves and removes `n` items from the queue" do
      check all(
              m <- non_negative_integer(),
              n <- integer(0..m),
              xs <- list_of(integer(), length: m),
              max_runs: @max_runs
            ) do
        queue = :queue.from_list(xs)
        {_, ys, remaining_queue} = Utils.pop_n(queue, n)

        assert ys == Enum.take(xs, n)
        assert :queue.len(remaining_queue) == max(m - n, 0)
      end
    end
  end

  describe "put_with_nil/3" do
    property "returns the original map when value is nil" do
      check all(
              map <- map_of(string(:ascii, min_length: 1, max_length: 10), integer()),
              key <- string(:ascii, min_length: 1, max_length: 10),
              max_runs: @max_runs
            ) do
        assert Utils.put_with_nil(map, key, nil) == map
      end
    end

    property "inserts key-value pair into the map when value is not nil" do
      check all(
              map <- map_of(string(:ascii, min_length: 1, max_length: 10), integer()),
              key <- string(:ascii, min_length: 1, max_length: 10),
              value <- integer(),
              max_runs: @max_runs
            ) do
        new_map = Utils.put_with_nil(map, key, value)

        assert new_map[key] == value
        assert map_size(new_map) == map_size(map) + if(Map.has_key?(map, key), do: 0, else: 1)
      end
    end
  end
end
