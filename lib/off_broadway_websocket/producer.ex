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

  @type outbound_frame :: {:text | :binary, iodata()}
  @type on_upgrade_result :: {:ok, [outbound_frame()]} | {:error, term()}
  @type frame_handler_result ::
          {:emit, [term()], term()}
          | {:skip, term()}
          | {:error, term(), term()}

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
    bootstrap_state = %State{state | conn_pid: conn_pid, stream_ref: stream_ref}

    case run_on_upgrade(bootstrap_state) do
      {:ok, ready_state} ->
        Telemetry.success(ready_state)

        if ready_state.ws_timeout do
          Process.send_after(self(), :check_timeout, ready_state.ws_timeout)
          Logger.debug(fn -> "[#{@me}] scheduled timeout check in #{ready_state.ws_timeout / 1_000}s" end)
        end

        {:noreply, [], %State{ready_state | last_msg_dt: DateTime.utc_now()}}

      {:error, reason, failed_state} ->
        bootstrap_failed(reason, failed_state)
    end
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
      {:data, payload}  -> handle_data_frame(pid, payload, state)
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
  defp do_connect(%State{ws_retry_opts: %{retries_left: 0}}) do
    Logger.warning("[#{@me}] retries exhausted")
    {:error, :max_retries_exhausted}
  end

  defp do_connect(state) do
    case Client.connect_once(state) do
      {:ok, conn_state} ->
        Logger.debug(fn -> "[#{@me}] connected to #{state.url}#{state.path}" end)
        new_state =
          state
          |> State.reset_frame_handler_state()
          |> Map.merge(%{ws_retry_opts: state.ws_init_retry_opts})
          |> Map.merge(conn_state)
        {:ok, new_state}

      {:error, reason} ->
        Logger.error("[#{@me}] connect failed: #{inspect(reason)}")

        Telemetry.fail(state, reason)

        updated_ws_retry_opts = state.ws_retry_fun.(state.ws_retry_opts)
        {:retry, updated_ws_retry_opts.delay, %{state | ws_retry_opts: updated_ws_retry_opts}}
    end
  end

  @spec dispatch_events(State.t()) :: {:noreply, list(any()), State.t()}
  defp dispatch_events(%State{total_demand: d, queue_size: q} = state) when d > 0 and q > 0 do
    {count, events, queue} = Utils.pop_items(state.message_queue, q, d)
    new_state = %State{state | message_queue: queue, queue_size: q - count, total_demand: d - count}
    {:noreply, events, new_state}
  end

  defp dispatch_events(state), do: {:noreply, [], state}

  defp handle_data_frame(_pid, payload, %State{frame_handler: nil} = state) do
    state
    |> State.update_on_msg(payload)
    |> dispatch_events()
  end

  defp handle_data_frame(_pid, payload, %State{frame_handler: {module, function, args}} = state) do
    case apply(module, function, [payload, state.frame_handler_state | args]) do
      {:emit, payloads, new_handler_state} when is_list(payloads) ->
        state
        |> with_frame_handler_state(new_handler_state)
        |> State.update_on_msgs(payloads)
        |> dispatch_events()

      {:skip, new_handler_state} ->
        state
        |> with_frame_handler_state(new_handler_state)
        |> State.update_last_msg_dt()
        |> dispatch_events()

      {:error, reason, new_handler_state} ->
        frame_handler_failed(reason, with_frame_handler_state(state, new_handler_state))

      other ->
        frame_handler_failed({:invalid_frame_handler_result, other}, state)
    end
  rescue
    error ->
      frame_handler_failed({:frame_handler_exception, error}, state)
  end

  defp run_on_upgrade(%State{on_upgrade: nil} = state), do: {:ok, state}

  defp run_on_upgrade(%State{on_upgrade: {module, function, args}} = state) do
    with {:ok, frames} <- apply(module, function, args),
         {:ok, _sent} <- send_outbound_frames(state.conn_pid, state.stream_ref, frames) do
      {:ok, state}
    else
      {:error, reason} -> {:error, reason, state}
      other -> {:error, {:invalid_on_upgrade_result, other}, state}
    end
  rescue
    error -> {:error, {:on_upgrade_exception, error}, state}
  end

  defp send_outbound_frames(_conn_pid, _stream_ref, []), do: {:ok, :empty}

  defp send_outbound_frames(conn_pid, stream_ref, frames) do
    Enum.reduce_while(frames, {:ok, 0}, fn frame, {:ok, sent_count} ->
      case :gun.ws_send(conn_pid, stream_ref, frame) do
        :ok ->
          {:cont, {:ok, sent_count + 1}}

        {:error, reason} ->
          {:halt, {:error, {:ws_send_failed, frame, reason}}}

        other ->
          {:halt, {:error, {:unexpected_ws_send_result, frame, other}}}
      end
    end)
  end

  defp bootstrap_failed(reason, %State{} = state) do
    Logger.error("[#{@me}] websocket bootstrap failed: #{inspect(reason)}")
    Telemetry.fail(state, {:bootstrap_failure, reason})

    updated_ws_retry_opts = state.ws_retry_fun.(state.ws_retry_opts)

    if state.conn_pid, do: :gun.shutdown(state.conn_pid)

    Process.send_after(self(), :connect, updated_ws_retry_opts.delay)

    {:noreply, [], %{state | conn_pid: nil, stream_ref: nil, ws_retry_opts: updated_ws_retry_opts}}
  end

  defp frame_handler_failed(reason, %State{} = state) do
    Logger.error("[#{@me}] inbound frame handler failed: #{inspect(reason)}")
    Telemetry.fail(state, {:frame_handler_failure, reason})

    updated_ws_retry_opts = state.ws_retry_fun.(state.ws_retry_opts)

    if state.conn_pid, do: :gun.shutdown(state.conn_pid)

    Process.send_after(self(), :connect, updated_ws_retry_opts.delay)

    failed_state =
      state
      |> State.reset_frame_handler_state()
      |> Map.put(:conn_pid, nil)
      |> Map.put(:stream_ref, nil)
      |> Map.put(:ws_retry_opts, updated_ws_retry_opts)

    {:noreply, [], failed_state}
  end

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

  defp with_frame_handler_state(state, new_handler_state) do
    %State{state | frame_handler_state: new_handler_state}
  end
end
