defmodule OffBroadwayWebSocket.UtilsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias OffBroadwayWebSocket.Utils

  @max_runs 100
  @max_items 100

  describe "pop_items/2" do
    test "pops no items when the queue is empty" do
      queue = :queue.new()

      assert {0, [], ^queue} = Utils.pop_items(queue, 0, 5)
    end

    property "pops correct number of items from the queue" do
      check all(
              n <- integer(0..@max_items),
              items <- list_of(integer())
            ) do
        queue = :queue.from_list(items)

        {count, popped_items, popped_queue} = Utils.pop_items(queue, Kernel.length(items), n)

        assert popped_items == Enum.take(items, n)
        assert count == min(Kernel.length(items), n)
        assert :queue.len(popped_queue) == :queue.len(queue) - count
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
