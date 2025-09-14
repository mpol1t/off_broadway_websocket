defmodule OffBroadwayWebSocket.Producer do
  @moduledoc """
  A `GenStage` producer that streams data from a WebSocket connection.

  Under the hood it relies on the **gun** library to establish and manage the
  connection. Incoming frames are buffered and dispatched based on the demand
  from Broadway consumers. Idle connections are supervised with ping/pong logic
  and automatic reconnection using a user supplied backoff strategy.
  """

  use GenStage
  require Logger

  alias OffBroadwayWebSocket.{Client, State, Utils, Handlers, Telemetry}

  @me __MODULE__

  @doc "Starts the WebSocket producer under a GenStage supervisor."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenStage.start_link(__MODULE__, opts)

  @impl true
  def init(opts) do
    send(self(), :connect)
    {:producer, %{State.new(opts) | pid: self()}}
  end

  @impl true
  def handle_info(:connect, state) do
    case do_connect(state) do
      {:ok, new_state} ->
        {:noreply, [], new_state}

      {:retry, delay, new_state} ->
        Logger.debug(fn -> "[#{@me}] reconnecting in #{delay / 1_000}s" end)
        Process.send_after(self(), :connect, delay)
        {:noreply, [], new_state}

      {:error, reason} ->
        Logger.error("[#{@me}] giving up: #{inspect(reason)}")
        {:stop, {:connection_failure, reason}, state}
    end
  end

  @impl true
  def handle_info({:gun_up, _pid, :http}, state), do: {:noreply, [], state}

  @impl true
  def handle_info({:gun_upgrade, conn_pid, stream_ref, ["websocket"], _headers}, state) do
    Logger.debug(fn -> "[#{@me}] WebSocket upgraded" end)

    Telemetry.success(state)

    if state.ws_timeout do
      Process.send_after(self(), :check_timeout, state.ws_timeout)
      Logger.debug(fn -> "[#{@me}] scheduled timeout check in #{state.ws_timeout / 1_000}s" end)
    end

    {:noreply, [], %State{state | conn_pid: conn_pid, stream_ref: stream_ref, last_msg_dt: DateTime.utc_now()}}
  end

  @impl true
  def handle_info({:gun_response, _conn_pid, _stream_ref, :nofin, status, headers}, state)
      when status >= 400 do
    Logger.error(
      "[#{@me}] WebSocket handshake failed with status #{status}, headers: #{inspect(headers)}"
    )

    {:stop, {:handshake_failure, {status, headers}}, state}
  end

  @impl true
  def handle_info({:gun_ws, pid, _ref, msg}, state) do
    case Handlers.normalize(msg) do
      {:data, payload}  -> State.update_on_msg(state, payload) |> dispatch_events()
      :pong             -> State.update_last_msg_dt(state) |> cont(:pong)
      :ping             -> cont(state, :ping)
      {:close, payload} -> halt(pid, state, payload)
    end
  end

  @impl true
  def handle_info({:gun_error, _,   _, reason},       state), do: handle_gun_error(reason, state)
  @impl true
  def handle_info({:gun_error, _,      reason},       state), do: handle_gun_error(reason, state)
  @impl true
  def handle_info({:gun_down,  pid, _, reason, _},    state), do: handle_gun_down(pid, reason, state)
  @impl true
  def handle_info({:gun_down,  pid, _, reason, _, _}, state), do: handle_gun_down(pid, reason, state)

  @impl true
  def handle_info(:check_timeout, state) do
    if stale_connection?(state.last_msg_dt, state.ws_timeout) do
      Logger.error("[#{@me}] timeout, closing")

      Telemetry.timeout(state)
      
      if state.conn_pid, do: :gun.shutdown(state.conn_pid)

      Process.send_after(self(), :connect, state.ws_retry_opts.delay)

      {:noreply, [], %State{state | conn_pid: nil, stream_ref: nil}}
    else
      Process.send_after(self(), :check_timeout, state.ws_timeout)
      {:noreply, [], state}
    end
  end

  defp stale_connection?(nil, _),       do: true
  defp stale_connection?(dt,  timeout), do: DateTime.diff(DateTime.utc_now(), dt, :second) > div(timeout, 1000)

  @impl true
  def handle_demand(incoming, state), do: dispatch_events(%State{state | total_demand: state.total_demand + incoming})

  @spec do_connect(State.t()) ::
          {:ok, State.t()}
          | {:retry, non_neg_integer(), State.t()}
          | {:error, :max_retries_exhausted | term()}
  @doc """
  Attempts to establish a new WebSocket connection using the configured client.

  Returns `{:ok, state}` on success, `{:retry, delay, state}` when another
  attempt should be scheduled, or `{:error, reason}` when retries are exhausted
  or an unrecoverable error occurs.
  """
  defp do_connect(%State{ws_retry_opts: %{retries_left: 0}}) do
    Logger.warning("[#{@me}] retries exhausted")
    {:error, :max_retries_exhausted}
  end

  defp do_connect(state) do
    case Client.connect_once(state) do
      {:ok, conn_state} ->
        Logger.debug(fn -> "[#{@me}] connected to #{state.url}#{state.path}" end)
        new_state = Map.merge(%{state | ws_retry_opts: state.ws_init_retry_opts}, conn_state)
        {:ok, new_state}

      {:error, reason} ->
        Logger.error("[#{@me}] connect failed: #{inspect(reason)}")

        Telemetry.fail(state, reason)

        updated_ws_retry_opts = state.ws_retry_fun.(state.ws_retry_opts)
        {:retry, updated_ws_retry_opts.delay, %{state | ws_retry_opts: updated_ws_retry_opts}}
    end
  end

  @spec dispatch_events(State.t()) :: {:noreply, list(any()), State.t()}
  @doc """
  Delivers buffered WebSocket messages when demand is available.

  Events are popped from the internal queue up to the current demand and
  returned to the Broadway pipeline. When not enough data is available, no
  messages are emitted and state is left unchanged.
  """
  defp dispatch_events(%State{total_demand: d, queue_size: q} = state) when d > 0 and q > 0 do
    {count, events, queue} = Utils.pop_items(state.message_queue, q, d)
    new_state = %State{state | message_queue: queue, queue_size: q - count, total_demand: d - count}
    {:noreply, events, new_state}
  end

  defp dispatch_events(state), do: {:noreply, [], state}

  @impl true
  def terminate(_reason, %State{conn_pid: pid} = state) do
    if pid, do: :gun.shutdown(pid)
    Logger.debug(fn -> "[#{@me}] shutting down" end)

    Telemetry.status(state, 0)
    
    :ok
  end

  defp cont(state, msg) do
    Logger.debug(fn -> "[#{@me}] received #{Atom.to_string(msg)}" end)
    {:noreply, [], state}
  end

  defp halt(pid, state, data) do
    suffix =
      case data do
        nil            -> ""
        {code, reason} -> ": code=#{code} reason=#{inspect(reason)}"
        payload        -> ": #{inspect(payload)}"
      end

    Logger.error("[#{@me}] websocket closed" <> suffix)
    Telemetry.disconnected(state, {:ws_close, data})

    :gun.shutdown(pid)
    Process.send_after(self(), :connect, state.ws_retry_opts.delay)

    {:noreply, [], %{state | conn_pid: nil, stream_ref: nil}}
  end

  defp handle_gun_down(conn_pid, reason, %State{ws_retry_opts: opts} = state) do
    case state.conn_pid do
      ^conn_pid ->
        Logger.error("[#{@me}] connection lost: #{inspect(reason)}")

        Telemetry.disconnected(state, reason)

        Process.send_after(self(), :connect, opts.delay)
        {:noreply, [], %{state | conn_pid: nil, stream_ref: nil}}

      _other ->
        Logger.debug(fn ->
          "[#{@me}] ignoring late gun_down for stale conn #{inspect(conn_pid)} (reason=#{inspect(reason)})"
        end)

        {:noreply, [], state}
    end
  end

  defp handle_gun_error(reason, state) do
    Logger.error("[#{@me}] gun connection error: #{inspect(reason)}")
    Telemetry.fail(state, reason)
    {:noreply, [], state}
  end
end
