defmodule OffBroadwayWebSocket.Utils do
  @moduledoc """
  Utility module for managing a queue with demand-based operations.
  """

  alias OffBroadwayWebSocket.Types

  @doc """
  Processes demand on the queue based on specified thresholds.

  If **size** is greater than or equal to **min_demand**, the function will attempt to
  pop up to **demand** items from the queue. If the **size** is less than **min_demand**,
  it returns an empty response.

  ## Parameters
    - **queue**: The queue from which to pull items (of type **:queue.queue()**).
    - **min_demand**: The minimum demand threshold (non-negative integer).
    - **size**: The current size of the queue (non-negative integer).
    - **demand**: The number of items requested (non-negative integer).

  ## Returns
    - A tuple **{count, items, new_queue}** where:
      - **count** is the number of items actually returned (non-negative integer).
      - **items** is a list of items retrieved from the queue.
      - **new_queue** is the updated queue after the demand is processed.
  """
  @spec on_demand(
          Types.queue(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {non_neg_integer(), list(), Types.queue()}
  def on_demand(queue,  min_demand,  size,  demand) when size >= min_demand,  do: pop_n(queue, demand)
  def on_demand(queue, _min_demand, _size, _demand),                          do: {0, [], queue}

  @doc """
  Retrieves up to **n** items from the queue.

  This function attempts to pop **n** items from the given queue. If the queue has fewer
  than **n** items, it retrieves as many as possible.

  ## Parameters
    - **queue**: The queue from which to pop items (of type **:queue.queue()**).
    - **n**: The number of items to retrieve (non-negative integer).

  ## Returns
    - A tuple **{count, items, new_queue}** where:
      - **count** is the actual number of items popped from the queue (non-negative integer).
      - **items** is a list of the retrieved items.
      - **new_queue** is the queue after items have been popped.
  """
  @spec pop_n(Types.queue(), non_neg_integer()) :: {non_neg_integer(), list(), Types.queue()}
  def pop_n(queue, n) when n >= 0, do: pop_n_aux(queue, n, [], 0)

  @doc false
  @spec pop_n_aux(
          Types.queue(), non_neg_integer(), list(), non_neg_integer()
        ) :: {non_neg_integer(), list(), Types.queue()}
  defp pop_n_aux(queue, 0, acc, counter), do: {counter, Enum.reverse(acc), queue}
  defp pop_n_aux(queue, n, acc, counter)  do
    case :queue.out(queue) do
      {{:value, v},  rest}  -> pop_n_aux(rest, n - 1, [ v | acc ], counter + 1)
      {:empty,      _rest}  -> {counter, Enum.reverse(acc), :queue.new()}
    end
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
  def put_with_nil(opts, _name, nil),      do: opts
  def put_with_nil(opts,  name, add_opts), do: Map.put(opts, name, add_opts)
end