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
              n     <- integer(0..@max_items),
              items <- list_of(integer()),
              max_runs: @max_runs
            ) do
        queue = :queue.from_list(items)

        {count, popped_items, popped_queue} = Utils.pop_items(queue, Kernel.length(items), n)

        assert popped_items             == Enum.take(items, n)
        assert count                    == min(Kernel.length(items), n)
        assert :queue.len(popped_queue) == :queue.len(queue) - count
      end
    end
  end
end
