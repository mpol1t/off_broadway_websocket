defmodule OffBroadwayWebSocket.State do
  @moduledoc """
  Holds the connection and retry state for a WebSocket producer in an Off-Broadway pipeline.

  ## Fields
  - **url**, **path** – Target WebSocket endpoint.
  - **gun_opts** – Options passed directly to Gun for HTTP/WebSocket setup.
  - **ws_timeout** – Idle timeout for WebSocket frames.
  - **await_timeout** – Timeout for synchronous Gun calls.
  - **headers** – HTTP headers for the upgrade.
  - **min_demand**, **max_demand** – Broadway demand settings.
  - **telemetry_id** – ID used when firing telemetry events.
  - **message_queue** – Internal buffer for frames before dispatch.
  - **ws_init_retry_opts**, **ws_retry_opts** – Retry parameters for reconnect logic.
  - **ws_retry_fun** – Function computing delays and next-state.
  - **pid**, **conn_pid**, **stream_ref** – Process and stream tracking.
  - **last_msg_dt**, **queue_size**, **total_demand** – Monitoring and backpressure.
  """

  @default_min_demand 10
  @default_max_demand 100
  @default_await_timeout 10_000
  @default_ws_reconnect_delay 10_000
  @default_ws_max_retries 5
  @default_telemetry_id :websocket_producer

  defstruct [
    # user-specified
    :url,
    :path,
    gun_opts: %{},
    ws_timeout: nil,
    await_timeout: @default_await_timeout,
    headers: [],
    min_demand: @default_min_demand,
    max_demand: @default_max_demand,
    telemetry_id: @default_telemetry_id,

    # retry logic
    ws_init_retry_opts: nil,
    ws_retry_opts: nil,
    ws_retry_fun: nil,

    # runtime state
    pid: nil,
    conn_pid: nil,
    stream_ref: nil,
    message_queue: :queue.new(),
    last_msg_dt: nil,
    queue_size: 0,
    total_demand: 0
  ]

  @type retry_opts :: %{
          required(:retries_left) => non_neg_integer(),
          required(:max_retries) => non_neg_integer(),
          required(:delay) => non_neg_integer()
        }

  @type retry_fun_return :: %{
          required(:opts) => retry_opts()
        }

  @type t :: %__MODULE__{
          url: String.t() | nil,
          path: String.t() | nil,
          gun_opts: map(),
          ws_timeout: non_neg_integer() | nil,
          await_timeout: non_neg_integer(),
          headers: [{String.t(), String.t()}],
          min_demand: non_neg_integer(),
          max_demand: non_neg_integer(),
          telemetry_id: atom(),
          message_queue: :queue.queue(any()),
          ws_init_retry_opts: retry_opts() | nil,
          ws_retry_opts: retry_opts() | nil,
          ws_retry_fun: (retry_opts() -> retry_fun_return()),
          pid: pid() | nil,
          conn_pid: pid() | nil,
          stream_ref: reference() | nil,
          last_msg_dt: DateTime.t() | nil,
          queue_size: non_neg_integer(),
          total_demand: non_neg_integer()
        }

  @doc """
  Builds a new state struct from the given options.

  Required options:
  - **:url** – WebSocket endpoint
  - **:path** – WebSocket path

  Optional:
  - **:gun_opts**, defaults to `%{}`
  - **:ws_timeout**, defaults to `nil`
  - **:await_timeout**, defaults to #{@default_await_timeout}
  - **:headers**, defaults to `[]`
  - **:telemetry_id**, defaults to #{inspect(@default_telemetry_id)}
  - **:broadway**, to customize min_demand/max_demand
  - **:ws_retry_opts**, defaults to default_ws_retry_opts/0
  """
  @spec new(keyword()) :: t()
  def new(opts) do
    {min_demand, max_demand} = parse_demand_opts(Keyword.get(opts, :broadway, []))
    retry_opts = Keyword.get(opts, :ws_retry_opts, default_ws_retry_opts())

    %__MODULE__{
      url: Keyword.fetch!(opts, :url),
      path: Keyword.fetch!(opts, :path),
      gun_opts: Keyword.get(opts, :gun_opts, %{}),
      ws_timeout: Keyword.get(opts, :ws_timeout, nil),
      await_timeout: Keyword.get(opts, :await_timeout, @default_await_timeout),
      headers: Keyword.get(opts, :headers, []),
      telemetry_id: Keyword.get(opts, :telemetry_id, @default_telemetry_id),
      min_demand: min_demand,
      max_demand: max_demand,
      ws_init_retry_opts: retry_opts,
      ws_retry_opts: retry_opts,
      ws_retry_fun: Keyword.get(opts, :ws_retry_fun, &default_ws_retry_fun/1)
    }
  end

  @spec parse_demand_opts(keyword()) :: {non_neg_integer(), non_neg_integer()}
  defp parse_demand_opts(broadway_opts) do
    procs = broadway_opts |> Keyword.get(:processors, []) |> Keyword.get(:default, [])
    min = Keyword.get(procs, :min_demand, @default_min_demand)
    max = Keyword.get(procs, :max_demand, @default_max_demand)
    {min, max}
  end

  @doc """
  The default retry options map used for WebSocket reconnects.
  """
  @spec default_ws_retry_opts() :: retry_opts()
  def default_ws_retry_opts do
    %{
      max_retries: @default_ws_max_retries,
      retries_left: @default_ws_max_retries,
      delay: @default_ws_reconnect_delay
    }
  end

  @doc """
  Default function to compute the next reconnect delay and state.
  """
  @spec default_ws_retry_fun(retry_opts()) :: retry_opts()
  def default_ws_retry_fun(%{retries_left: 0, delay: delay} = opts),
    do: %{opts | retries_left: 0, delay: delay}

  def default_ws_retry_fun(%{retries_left: n, delay: delay} = opts) when n > 0 do
    %{opts | retries_left: n - 1, delay: delay}
  end
end
