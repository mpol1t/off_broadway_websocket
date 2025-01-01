defmodule OffBroadwayWebSocket.State do
  alias OffBroadwayWebSocket.Types

  @moduledoc """
  Manages the state for WebSocket producer in an Off-Broadway setup.
  This includes demand tracking, reconnection parameters, and message queuing.
  """

  @default_min_demand 10
  @default_max_demand 100
  @default_await_timeout 10_000
  @default_connect_timeout 60_000
  @default_event_producer_id :websocket_producer

  defstruct [
    :url,
    :path,
    :min_demand,
    :max_demand,
    :message_queue,
    :ws_timeout,
    :await_timeout,
    :connect_timeout,
    :http_opts,
    :ws_opts,
    :event_producer_id,
    conn_pid: nil,
    stream_ref: nil,
    last_pong: nil,
    queue_size: 0,
    total_demand: 0,
    headers: []
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
          headers: list(),
          event_producer_id: atom()
        }

  @doc """
  Creates a new **%State{}** struct with specified options.

  ## Parameters
    - **opts**: A keyword list of options, including:
      - **:broadway** - Broadway-related options, specifically demand settings.
      - **:url** - The WebSocket URL.
      - **:path** - The WebSocket path.
      - **:ws_opts** - WebSocket options for **gun**.
      - **:http_opts** - HTTP options for **gun**.
      - **:ws_timeout** - Optional timeout for WebSocket operations.
      - **:headers:** - Optional headers to use when upgrading to WebSocket.
      - **:event_producer_id** - Optional ID to be used when emitting telemetry events. Defaults to :websocket_producer

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
      headers: Keyword.get(opts, :headers, []),
      event_producer_id: Keyword.get(opts, :event_producer_id, @default_event_producer_id)
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
end
