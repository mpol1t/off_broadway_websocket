defmodule OffBroadwayWebSocket.Producer do
  @moduledoc """
  A GenStage producer that manages WebSocket connections using the **gun** library.

  This module establishes a WebSocket connection, and manages message dispatching based on demand. It monitors the
  WebSocket connection with ping/pong messages and terminates connection when timeouts occur.
  """

  use GenStage
  require Logger

  alias OffBroadwayWebSocket.Client
  alias OffBroadwayWebSocket.State
  alias OffBroadwayWebSocket.Utils

  @behaviour Broadway.Producer

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    state = State.new(opts)

    case Client.connect(
           state.url,
           state.path,
           {state.http_opts, state.ws_opts},
           state.await_timeout,
           state.connect_timeout
         ) do
      {:ok, conn_state} ->
        Logger.debug("[Producer] Connected successfully to #{state.url}#{state.path}")
        {:producer, Map.merge(state, conn_state)}

      {:error, reason} ->
        :telemetry.execute([:websocket_producer, :connection, :failure], %{count: 1}, %{
          reason: reason
        })

        Logger.error("[Producer] Failed to connect: #{inspect(reason)}")
    end
  end

  @impl true
  def handle_info(
        {:gun_upgrade, conn_pid, stream_ref, ["websocket"], _headers},
        %State{ws_timeout: t} = state
      ) do
    :telemetry.execute([:websocket_producer, :connection, :success], %{count: 1}, %{
      url: "#{state.url}#{state.path}"
    })

    Logger.debug("[Producer] WebSocket upgrade message received.")

    case t do
      nil ->
        nil

      _ ->
        Logger.debug("[Producer] First timeout check scheduled in #{t / 1_000}s")
        Process.send_after(self(), :check_ws_timeout, t)
    end

    {:noreply, [], %State{state | conn_pid: conn_pid, stream_ref: stream_ref}}
  end

  def handle_info({:gun_response, _conn_pid, _stream_ref, _flag, _status, _headers}, state) do
    {:noreply, [], state}
  end

  # Handling :gun_data
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
  def handle_info(
        {:gun_ws, _conn_pid, _stream_ref, {_, msg}},
        %State{message_queue: q, queue_size: s} = state
      ) do
    dispatch_events(%State{state | message_queue: :queue.in(msg, q), queue_size: s + 1}, 0)
  end

  @impl true
  def handle_info({:gun_down, conn_pid, _protocol, reason, _killed_streams}, state) do
    Logger.error("[Producer] Connection lost: #{inspect(reason)}. Scheduling reconnect.")

    :telemetry.execute([:websocket_producer, :connection, :disconnected], %{count: 1}, %{
      reason: reason
    })

    :ok = :gun.close(conn_pid)
    {:stop, {:error, reason}, state}
  end

  @impl true
  def handle_info(:check_ws_timeout, %State{last_pong: nil} = state) do
    on_ws_timeout(state)
  end

  @impl true
  def handle_info(:check_ws_timeout, %State{ws_timeout: ws_timeout, last_pong: t} = state) do
    case DateTime.diff(DateTime.utc_now(), t) > ws_timeout / 1_000 do
      true ->
        on_ws_timeout(state)

      false ->
        Process.send_after(self(), :check_ws_timeout, ws_timeout)
        {:noreply, [], state}
    end
  end

  @doc """
  Closes the connection and schedules a reconnect on WebSocket timeout.
  """
  def on_ws_timeout(%State{conn_pid: conn_pid} = state) do
    Logger.error("[Producer] Ping/Pong timeout. Scheduling reconnect.")
    :telemetry.execute([:websocket_producer, :connection, :timeout], %{count: 1}, %{})
    :ok = :gun.close(conn_pid)
    {:stop, {:error, :timeout}, state}
  end

  @impl true
  def handle_demand(incoming_demand, state) do
    dispatch_events(state, incoming_demand)
  end

  @spec dispatch_events(State.t(), non_neg_integer()) :: {atom(), list(), State.t()}
  def dispatch_events(
        %State{message_queue: q, total_demand: d, queue_size: s, min_demand: m} = state,
        incoming_demand
      ) do
    new_demand = d + incoming_demand

    {c, events, rest} = Utils.on_demand(q, m, s, new_demand)

    {:noreply, events,
     %State{state | total_demand: new_demand - c, message_queue: rest, queue_size: s - c}}
  end

  @impl true
  def terminate(_reason, %{conn_pid: conn_pid}) when not is_nil(conn_pid) do
    :gun.close(conn_pid)
    Logger.debug("[Producer] Terminating and closing connection.")
    :ok
  end

  def terminate(_reason, _state), do: :ok
end
