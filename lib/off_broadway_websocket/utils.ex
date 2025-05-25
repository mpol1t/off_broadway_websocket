defmodule OffBroadwayWebSocket.Utils do
  @moduledoc false

  @doc """
  Pops items from the given queue.

  ## Parameters

    - **queue**: The queue to pop items from.
    - **m**: The current number of items in the queue.
    - **n**: The number of items requested to be removed.

  ## Behavior

    - If **n** is greater than **m**, all **m** items are returned and the queue is emptied.
    - If either **m** or **n** is zero, no items are removed.
    - Otherwise, up to **n** items are removed from the queue.

  ## Returns

  A tuple **{popped_count, items, new_queue}** where:
    - **popped_count** is the number of items actually removed.
    - **items** is the list of removed items.
    - **new_queue** is the remaining queue after removal.
  """
  @spec pop_items(:queue.queue(), non_neg_integer(), non_neg_integer()) ::
          {non_neg_integer(), list(), :queue.queue()}
  def pop_items(queue, 0, _), do: {0, [], queue}
  def pop_items(queue, _, 0), do: {0, [], queue}
  def pop_items(queue, m, n) when n > m, do: {m, :queue.to_list(queue), :queue.new()}

  def pop_items(queue, _, n) do
    {front, back} = :queue.split(n, queue)
    popped_items = :queue.to_list(front)
    popped_count = length(popped_items)

    {popped_count, popped_items, back}
  end
end
