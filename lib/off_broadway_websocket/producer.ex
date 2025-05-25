defmodule OffBroadwayWebSocket.Producer do
  @moduledoc """
  A GenStage producer that manages WebSocket connections using the **gun** library.

  This module establishes a WebSocket connection, and manages message dispatching based on demand. It monitors the
  WebSocket connection with ping/pong messages and terminates connection when timeouts occur.
  """

  use GenStage

  alias OffBroadwayWebSocket.State
  alias OffBroadwayWebSocket.Utils

  require Logger

  @me __MODULE__

  @doc "Starts the WebSocket producer under a GenStage supervisor."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

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

    :telemetry.execute([state.telemetry_id, :connection, :success], %{count: 1}, %{
      url: state.url <> state.path
    })

    if state.ws_timeout do
      Process.send_after(self(), :check_timeout, state.ws_timeout)
      Logger.debug(fn -> "[#{@me}] scheduled timeout check in #{state.ws_timeout / 1_000}s" end)
    end

    {:noreply, [], %{state | conn_pid: conn_pid, stream_ref: stream_ref}}
  end

  @impl true
  def handle_info({:gun_ws, _conn_pid, _stream_ref, :ping}, state) do
    Logger.debug(fn -> "[#{@me}] received ping" end)
    {:noreply, [], state}
  end

  @impl true
  def handle_info({:gun_ws, _pid, _ref, :pong}, state) do
    Logger.debug(fn -> "[#{@me}] received pong" end)
    {:noreply, [], %{state | last_msg_dt: DateTime.utc_now()}}
  end

  @impl true
  def handle_info({:gun_ws, _pid, _ref, {_, msg}}, state) do
    updated = %{
      state
      | message_queue: :queue.in(msg, state.message_queue),
        queue_size: state.queue_size + 1,
        last_msg_dt: DateTime.utc_now()
    }

    dispatch_events(updated)
  end

  @impl true
  def handle_info({:gun_down, pid, _proto, reason, _streams}, %State{conn_pid: pid, ws_retry_opts: opts} = state) do
    Logger.error("[#{@me}] connection lost: #{inspect(reason)}")
    :gun.shutdown(pid)

    :telemetry.execute([state.telemetry_id, :connection, :disconnected], %{count: 1}, %{
      reason: reason
    })

    Process.send_after(self(), :connect, opts.delay)
    {:noreply, [], %{state | conn_pid: nil, stream_ref: nil}}
  end

  @impl true
  def handle_info(
        :check_timeout,
        %State{last_msg_dt: last_msg, ws_timeout: timeout, ws_retry_opts: opts, conn_pid: pid} = state
      ) do
    stale = last_msg == nil or DateTime.diff(DateTime.utc_now(), last_msg) > timeout / 1_000

    if stale do
      Logger.error("[#{@me}] timeout, closing")
      :telemetry.execute([state.telemetry_id, :connection, :timeout], %{count: 1}, %{})
      :gun.shutdown(pid)
      Process.send_after(self(), :connect, opts.delay)
      {:noreply, [], %{state | conn_pid: nil, stream_ref: nil}}
    else
      Process.send_after(self(), :check_timeout, timeout)
      {:noreply, [], state}
    end
  end

  @impl true
  def handle_demand(incoming, state) do
    dispatch_events(%{state | total_demand: state.total_demand + incoming})
  end

  @spec do_connect(State.t()) ::
          {:ok, State.t()} | {:retry, non_neg_integer(), State.t()} | {:error, any()}
  defp do_connect(%State{ws_retry_opts: %{retries_left: 0}}) do
    Logger.warning("[#{@me}] retries exhausted")
    {:error, :max_retries_exhausted}
  end

  defp do_connect(state) do
    client = Application.get_env(:off_broadway_websocket, :client, OffBroadwayWebSocket.Client)

    case client.connect(state.url, state.path, state.gun_opts, state.await_timeout, state.headers) do
      {:ok, conn_state} ->
        Logger.debug(fn -> "[#{@me}] connected to #{state.url}#{state.path}" end)

        new_state = Map.merge(%{state | ws_retry_opts: state.ws_init_retry_opts}, conn_state)

        {:ok, new_state}

      {:error, reason} ->
        Logger.error("[#{@me}] connect failed: #{inspect(reason)}")

        :telemetry.execute([state.telemetry_id, :connection, :failure], %{count: 1}, %{
          reason: reason
        })

        updated_ws_retry_opts = state.ws_retry_fun.(state.ws_retry_opts)

        {:retry, updated_ws_retry_opts.delay, %{state | ws_retry_opts: updated_ws_retry_opts}}
    end
  end

  @spec dispatch_events(State.t()) :: {:noreply, list(any()), State.t()}
  defp dispatch_events(state) do
    if state.queue_size >= state.min_demand do
      {count, events, queue} =
        Utils.pop_items(state.message_queue, state.queue_size, state.total_demand)

      new_state = %{
        state
        | message_queue: queue,
          queue_size: state.queue_size - count,
          total_demand: state.total_demand - count
      }

      {:noreply, events, new_state}
    else
      {:noreply, [], state}
    end
  end

  @impl true
  def terminate(_reason, %State{conn_pid: pid} = state) do
    if pid, do: :gun.shutdown(pid)
    Logger.debug(fn -> "[#{@me}] shutting down" end)
    :telemetry.execute([state.telemetry_id, :connection, :status], %{value: 0}, %{})
    :ok
  end
end
