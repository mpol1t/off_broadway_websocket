defmodule OffBroadwayWebSocket.Producer do
  @moduledoc """
  A GenStage producer that manages WebSocket connections using the **gun** library.

  This module establishes a WebSocket connection, and manages message dispatching based on demand. It monitors the
  WebSocket connection with ping/pong messages and terminates connection when timeouts occur.
  """

  use GenStage
  require Logger

  #  alias OffBroadwayWebSocket.Client
  alias OffBroadwayWebSocket.State
  alias OffBroadwayWebSocket.Utils

  @behaviour Broadway.Producer
  @me __MODULE__

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    state = %State{State.new(opts) | pid: @me}

    case impl().connect(
           state.url,
           state.path,
           {state.http_opts, state.ws_opts},
           state.await_timeout,
           state.connect_timeout,
           state.headers
         ) do
      {:ok, conn_state} ->
        Logger.debug(fn -> "[#{@me}] Connected successfully to #{state.url}#{state.path}" end)
        {:producer, Map.merge(state, conn_state)}

      {:error, reason} ->
        :telemetry.execute([state.telemetry_id, :connection, :failure], %{count: 1}, %{
          reason: reason
        })

        Logger.error("[#{@me}] Failed to connect: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_info({:gun_upgrade, conn_pid, stream_ref, ["websocket"], _headers}, state) do
    :telemetry.execute([state.telemetry_id, :connection, :success], %{count: 1}, %{
      url: "#{state.url}#{state.path}"
    })

    :telemetry.execute([state.telemetry_id, :connection, :status], %{value: 1}, %{})

    Logger.debug(fn -> "[#{@me}] WebSocket upgrade message received." end)

    case state.ws_timeout do
      nil ->
        nil

      _ ->
        Logger.debug(fn ->
          "[#{@me}] First timeout check scheduled in #{state.ws_timeout / 1_000}s"
        end)

        Process.send_after(state.pid, :check_ws_timeout, state.ws_timeout)
    end

    {:noreply, [], %State{state | conn_pid: conn_pid, stream_ref: stream_ref}}
  end

  def handle_info({:gun_response, _conn_pid, _stream_ref, _flag, _status, _headers}, state) do
    {:noreply, [], state}
  end

  def handle_info({:gun_data, _conn_pid, _stream_ref, _flag, _data}, state) do
    {:noreply, [], state}
  end

  @impl true
  def handle_info({:gun_ws, _conn_pid, _stream_ref, :pong}, state) do
    {:noreply, [], %State{state | last_pong: DateTime.utc_now()}}
  end

  @impl true
  def handle_info({:gun_ws, _conn_pid, _stream_ref, :ping}, state) do
    {:noreply, [], state}
  end

  @impl true
  def handle_info({:gun_ws, _conn_pid, _stream_ref, {_, msg}}, state) do
    dispatch_events(%State{
      state
      | message_queue: :queue.in(msg, state.message_queue),
        queue_size: state.queue_size + 1
    })
  end

  @impl true
  def handle_info({:gun_down, conn_pid, _protocol, reason, _killed_streams}, state) do
    Logger.error("[#{@me}] Connection lost: #{inspect(reason)}")

    :gun.close(conn_pid)

    :telemetry.execute([state.telemetry_id, :connection, :disconnected], %{count: 1}, %{
      reason: reason
    })

    {:stop, {:error, reason}, state}
  end

  @impl true
  def handle_info(:check_ws_timeout, state) do
    trigger_timeout =
      case state.last_pong do
        nil -> true
        _ -> DateTime.diff(DateTime.utc_now(), state.last_pong) > state.ws_timeout / 1_000
      end

    if trigger_timeout do
      Logger.error("[#{@me}] Ping/Pong timeout. Closing connection...")

      :telemetry.execute([state.telemetry_id, :connection, :timeout], %{count: 1}, %{})
      :gun.close(state.conn_pid)

      {:stop, {:error, :timeout}, state}
    else
      Process.send_after(state.pid, :check_ws_timeout, state.ws_timeout)
      {:noreply, [], state}
    end
  end

  @impl true
  def handle_demand(incoming_demand, state) do
    dispatch_events(%State{state | total_demand: state.total_demand + incoming_demand})
  end

  @spec dispatch_events(State.t()) :: {atom(), list(), State.t()}
  def dispatch_events(state) do
    {count, events, queue} =
      if state.queue_size >= state.min_demand do
        # Enough items to proceed with dispatch.
        Utils.pop_items(state.message_queue, state.queue_size, state.total_demand)
      else
        # Not enough items in the message queue. Register demand.
        {0, [], state.message_queue}
      end

    {:noreply, events,
     %State{
       state
       | total_demand: state.total_demand - count,
         message_queue: queue,
         queue_size: state.queue_size - count
     }}
  end

  @impl true
  def terminate(_reason, state) do
    case state.conn_pid do
      nil -> nil
      _ -> :gun.close(state.conn_pid)
    end

    Logger.debug(fn -> "[#{@me}] Connection closed." end)
    :telemetry.execute([state.telemetry_id, :connection, :status], %{value: 0}, %{})

    :ok
  end

  defp impl,
    do: Application.get_env(:off_broadway_websocket, :client, OffBroadwayWebSocket.Client)
end
