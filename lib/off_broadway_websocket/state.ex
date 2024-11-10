defmodule OffBroadwayWebSocket.State do
  alias OffBroadwayWebSocket.Types

  @moduledoc """
  Manages the state for WebSocket producer in an Off-Broadway setup.
  This includes demand tracking, reconnection parameters, and message queuing.
  """

  @default_min_demand 10
  @default_max_demand 100
  @default_reconnect_delay 5_000
  @default_reconnect_initial_delay 1_000
  @default_reconnect_max_delay 60_000
  @default_await_timeout 10_000
  @default_connect_timeout 60_000

  defstruct [
    :url,
    :path,
    :min_demand,
    :max_demand,
    :message_queue,
    :reconnect_initial_delay,
    :reconnect_max_delay,
    :reconnect_delay,
    :ws_timeout,
    :await_timeout,
    :connect_timeout,
    :http_opts,
    :ws_opts,
    conn_pid: nil,
    stream_ref: nil,
    last_pong: nil,
    queue_size: 0,
    total_demand: 0,
    reconnect_attempts: 0
  ]

  @type t :: %__MODULE__{
          url: String.t(),
          path: String.t(),
          conn_pid: pid() | nil,
          stream_ref: reference() | nil,
          message_queue: Types.queue(),
          ws_opts: map(),
          http_opts: map(),
          last_pong: DateTime.t() | nil,
          await_timeout: non_neg_integer(),
          connect_timeout: non_neg_integer(),
          ws_timeout: non_neg_integer(),
          min_demand: non_neg_integer(),
          max_demand: non_neg_integer(),
          queue_size: non_neg_integer(),
          total_demand: non_neg_integer(),
          reconnect_delay: non_neg_integer(),
          reconnect_attempts: non_neg_integer(),
          reconnect_max_delay: non_neg_integer(),
          reconnect_initial_delay: non_neg_integer()
        }

  @doc """
  Creates a new **%State{}** struct with specified options.

  ## Parameters
    - **opts**: A keyword list of options, including:
      - **:broadway** - Broadway-related options, specifically demand settings.
      - **:url** - The WebSocket URL.
      - **:path** - The WebSocket path.
      - **:reconnect_delay** - Optional delay in milliseconds for reconnection.
      - **:ws_opts** - WebSocket options for **gun**.
      - **:http_opts** - HTTP options for **gun**.
      - **:ws_timeout** - Optional timeout for WebSocket operations.

  ## Returns
    - A **%State{}** struct initialized with the provided options and default values.
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    {min_demand, max_demand} = get_min_max_demand(Keyword.get(opts, :broadway))

    %__MODULE__{
      min_demand: min_demand,
      max_demand: max_demand,
      message_queue: :queue.new(),
      url: Keyword.get(opts, :url),
      path: Keyword.get(opts, :path),
      ws_opts: Keyword.get(opts, :ws_opts, nil),
      http_opts: Keyword.get(opts, :http_opts, nil),
      ws_timeout: Keyword.get(opts, :ws_timeout, nil),
      await_timeout: Keyword.get(opts, :await_timeout, @default_await_timeout),
      connect_timeout: Keyword.get(opts, :connect_timeout, @default_connect_timeout),
      reconnect_delay: Keyword.get(opts, :reconnect_delay, @default_reconnect_delay),
      reconnect_max_delay: Keyword.get(opts, :reconnect_max_delay, @default_reconnect_max_delay),
      reconnect_initial_delay:
        Keyword.get(opts, :reconnect_initial_delay, @default_reconnect_initial_delay)
    }
  end

  @doc false
  @spec get_min_max_demand(keyword() | nil) :: {non_neg_integer(), non_neg_integer()}
  defp get_min_max_demand(opts) do
    default_processors = Keyword.get(opts || [], :processors, []) |> Keyword.get(:default, [])

    {
      Keyword.get(default_processors, :min_demand, @default_min_demand),
      Keyword.get(default_processors, :max_demand, @default_max_demand)
    }
  end

  @doc """
  Resets the reconnect state within a **%State{}** struct.

  Sets **reconnect_attempts** to **0** and resets **reconnect_delay** to
  the initial delay specified by **@default_reconnect_initial_delay**.

  ## Parameters
    - **state**: The **%State{}** struct whose reconnect state is being reset.

  ## Returns
    - An updated **%State{}** struct with **reconnect_attempts** set to **0**
      and **reconnect_delay** set to **@default_reconnect_initial_delay**.
  """
  @spec reset_reconnect_state(t()) :: t()
  def reset_reconnect_state(%__MODULE__{reconnect_initial_delay: reconnect_initial_delay} = state) do
    %__MODULE__{state | reconnect_attempts: 0, reconnect_delay: reconnect_initial_delay}
  end
end
