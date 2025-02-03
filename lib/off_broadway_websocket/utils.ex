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

  @doc """
  Conditionally adds a key-value pair to a map if the value is not **nil**.

  If the provided value is **nil**, the function returns the original map without modification.
  Otherwise, it adds the key-value pair to the map.

  ## Parameters
    - **opts**: The initial map to which the key-value pair may be added.
    - **name**: The key to add to the map if **add_opts** is not **nil**.
    - **add_opts**: The value to associate with **name**. If **nil**, **opts** is returned unmodified.

  ## Returns
    - The updated map if **add_opts** is not **nil**.
    - The original map if **add_opts** is **nil**.
  """
  @spec put_with_nil(map(), any(), any() | nil) :: map()
  def put_with_nil(opts, _name, nil), do: opts
  def put_with_nil(opts, name, add_opts), do: Map.put(opts, name, add_opts)
end
