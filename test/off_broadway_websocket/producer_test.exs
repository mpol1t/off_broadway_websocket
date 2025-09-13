defmodule OffBroadwayWebSocket.ProducerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mox

  alias OffBroadwayWebSocket.Producer
  alias OffBroadwayWebSocket.State

  @test_opts [
    broadway: [processors: [default: [min_demand: 0, max_demand: 100]]],
    url: "wss://api.test.com",
    path: "/v1/test-endpoint",
    ws_timeout: 30_000,
    gun_opts: %{keepalive: 15_000},
    telemetry_id: :dummy_telemetry
  ]

  setup :set_mox_from_context
  setup :verify_on_exit!

  describe "init/1" do
    test "successful connection" do
      expect(OffBroadwayWebSocket.MockClient, :connect, fn _url, _path, _opts, _await, _headers ->
        {:ok, %{conn_pid: :fake, stream_ref: :ref}}
      end)

      capture =
        capture_log(fn ->
          {:ok, pid} = Producer.start_link(@test_opts)
          send(self(), {:started, pid})
          Process.sleep(10)
        end)

      assert capture =~ "connected to wss://api.test.com/v1/test-endpoint"
      assert_receive {:started, pid}, 500

      %GenStage{state: state} = :sys.get_state(pid)
      assert state.conn_pid == :fake
      assert state.stream_ref == :ref
    end

    test "failed connection emits telemetry and schedules retry" do
      test_pid = self()

      :telemetry.attach(
        :fail,
        [:dummy_telemetry, :connection, :failure],
        fn _event, measurements, metadata, _ ->
          send(test_pid, {:failed, measurements, metadata})
        end,
        nil
      )

      expect(OffBroadwayWebSocket.MockClient, :connect, fn _url, _path, _opts, _await, _headers ->
        {:error, :fail}
      end)

      capture =
        capture_log(fn ->
          {:ok, _pid} = Producer.start_link(@test_opts)
          # allow the async :connect to happen
          Process.sleep(50)
        end)

      assert capture =~ "connect failed: :fail"
      assert capture =~ "reconnecting in"
      assert_receive {:failed, %{count: 1}, %{reason: :fail}}, 500

      :telemetry.detach(:fail)
    end
  end

  describe "handle_info(:gun_upgrade)" do
    setup do
      pid = self()

      :telemetry.attach(
        :success,
        [:dummy_telemetry, :connection, :success],
        fn _e, ms, md, _ -> send(pid, {:success, ms, md}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(:success) end)
      :ok
    end

    test "schedules timeout when ws_timeout set" do
      conn = self()
      state = %{State.new(@test_opts) | ws_timeout: 100, pid: self()}

      capture =
        capture_log(fn ->
          {:noreply, [], new_state} =
            Producer.handle_info(
              {:gun_upgrade, conn, :ref, ["websocket"], []},
              state
            )

          assert new_state.conn_pid == conn
          assert new_state.stream_ref == :ref
        end)

      assert capture =~ "scheduled timeout"
      assert_receive {:success, %{count: 1}, %{url: "wss://api.test.com/v1/test-endpoint"}}, 500
      assert_receive :check_timeout, 200
    end

    test "does not schedule timeout when ws_timeout nil" do
      conn = self()
      state = %{State.new(@test_opts) | ws_timeout: nil, pid: self()}

      capture =
        capture_log(fn ->
          {:noreply, [], new_state} =
            Producer.handle_info(
              {:gun_upgrade, conn, :ref, ["websocket"], []},
              state
            )

          assert new_state.conn_pid == conn
          assert new_state.stream_ref == :ref
        end)

      assert capture =~ "WebSocket upgraded"
      assert_receive {:success, %{count: 1}, %{url: "wss://api.test.com/v1/test-endpoint"}}, 500
      refute_receive :check_timeout
    end
  end

  describe "handle_info(:gun_response)" do
    test "logs and returns correct values" do
      state = %{State.new(@test_opts) | pid: self()}

      capture = capture_log(
        fn ->
           {:stop, {:handshake_failure, {400, ["returned_headers"]}}, _state} =
             Producer.handle_info(
               {:gun_response, nil, :ref, :nofin, 400, ["returned_headers"]}, state
             ) 
        end
      )

      assert capture =~ "WebSocket handshake failed with status 400, headers: [\"returned_headers\"]"
    end
  end
  

  describe "handle_info for ws frames" do
    test ":pong updates last_msg_dt" do
      {:noreply, [], state} =
        Producer.handle_info({:gun_ws, nil, nil, :pong}, State.new(@test_opts))

      assert state.last_msg_dt != nil
    end

    test ":ping no change" do
      state = State.new(@test_opts)
      {:noreply, [], new_state} = Producer.handle_info({:gun_ws, nil, nil, :ping}, state)
      assert new_state == state
    end

    test "text enqueues when no demand" do
      msg = "hi"

      {:noreply, [], state} =
        Producer.handle_info({:gun_ws, nil, nil, {:text, msg}}, State.new(@test_opts))

      assert state.queue_size == 1
    end

    test "text dispatches when demand" do
      msg = "hi"
      state = %{State.new(@test_opts) | total_demand: 1}

      {:noreply, [^msg], new_state} =
        Producer.handle_info({:gun_ws, nil, nil, {:text, msg}}, state)

      assert new_state.queue_size == 0
    end
  end

  describe "handle_info(:gun_down)" do
    test "logs and emits telemetry, schedules reconnect (no shutdown called here)" do
      conn = self()
      pid = self()

      :telemetry.attach(
        :disc,
        [:dummy_telemetry, :connection, :disconnected],
        fn _e, ms, md, _ -> send(pid, {:disc, ms, md}) end,
        nil
      )

      # No meck here — producer doesn't call :gun.shutdown on :gun_down
      state = %{State.new(@test_opts) | conn_pid: conn, ws_retry_opts: %{delay: 5, retries_left: 1, max_retries: 1}}

      capture =
        capture_log(fn ->
          {:noreply, [], new_state} =
            Producer.handle_info({:gun_down, conn, :proto, :reason, []}, state)

          assert new_state.conn_pid == nil
          assert new_state.stream_ref == nil
        end)

      assert capture =~ "connection lost: :reason"
      assert_receive {:disc, %{count: 1}, %{reason: :reason}}, 200
      assert_receive :connect, 200

      :telemetry.detach(:disc)
    end
  end

  describe "handle_info(:check_timeout)" do
    test "timeout triggers reconnect" do
      conn = self()
      state = %{State.new(@test_opts) | conn_pid: conn, pid: conn, ws_timeout: 1}

      pid = self()

      :telemetry.attach(
        :to,
        [:dummy_telemetry, :connection, :timeout],
        fn _e, ms, md, _ -> send(pid, {:to, ms, md}) end,
        nil
      )

      :meck.new(:gun, [:non_strict])

      :meck.expect(:gun, :shutdown, fn ^conn ->
        send(pid, :down)
        :ok
      end)

      capture =
        capture_log(fn ->
          {:noreply, [], new_state} = Producer.handle_info(:check_timeout, state)
          assert new_state.conn_pid == nil
        end)

      assert capture =~ "timeout"
      assert_receive :down, 500
      assert_receive {:to, %{count: 1}, %{}}, 500

      :meck.unload(:gun)
      :telemetry.detach(:to)
    end

    test "recent last_msg_dt reschedules" do
      state = %{
        State.new(@test_opts)
        | last_msg_dt: DateTime.utc_now(),
          ws_timeout: 100,
          pid: self()
      }

      assert {:noreply, [], ^state} = Producer.handle_info(:check_timeout, state)
      assert_receive :check_timeout, 200
    end
  end

  describe "handle_demand/2" do
    test "dispatches available events" do
      state = %{
        State.new(@test_opts)
        | message_queue: :queue.from_list([1, 2]),
          queue_size: 2
      }

      assert {:noreply, [1], new_state} = Producer.handle_demand(1, state)
      assert new_state.queue_size == 1
    end

    test "queues demand when insufficient" do
      state = %{
        State.new(@test_opts)
        | message_queue: :queue.new(),
          queue_size: 0,
          total_demand: 0,
          min_demand: 5
      }

      assert {:noreply, [], new_state} = Producer.handle_demand(3, state)
      assert new_state.total_demand == 3
    end
  end

  describe "terminate/2" do
    test "shutdowns when conn_pid" do
      conn = self()
      pid = self()

      :telemetry.attach(
        :stat,
        [:dummy_telemetry, :connection, :status],
        fn _e, ms, md, _ -> send(pid, {:stat, ms, md}) end,
        nil
      )

      :meck.new(:gun, [:non_strict])

      :meck.expect(:gun, :shutdown, fn ^conn ->
        send(pid, :down)
        :ok
      end)

      capture =
        capture_log(fn ->
          assert :ok = Producer.terminate(:reason, %{State.new(@test_opts) | conn_pid: conn})
        end)

      assert capture =~ "shutting down"
      assert_receive :down, 500
      assert_receive {:stat, %{value: 0}, %{}}, 500

      :meck.unload(:gun)
      :telemetry.detach(:stat)
    end

    test "no shutdown when nil conn_pid" do
      pid = self()

      :telemetry.attach(
        :stat2,
        [:dummy_telemetry, :connection, :status],
        fn _e, ms, md, _ -> send(pid, {:stat2, ms, md}) end,
        nil
      )

      :meck.new(:gun, [:non_strict])
      :meck.expect(:gun, :shutdown, fn _ -> flunk("called") end)

      capture =
        capture_log(fn ->
          assert :ok = Producer.terminate(:reason, State.new(@test_opts))
        end)

      assert capture =~ "shutting down"
      assert_receive {:stat2, %{value: 0}, %{}}, 500

      :meck.unload(:gun)
      :telemetry.detach(:stat2)
    end
  end

  describe "handle_info for ws frames (new clauses)" do
    test ":pong with payload updates last_msg_dt" do
      {:noreply, [], state} =
        Producer.handle_info({:gun_ws, nil, nil, {:pong, "x"}}, State.new(@test_opts))

      assert state.last_msg_dt != nil
    end

    test ":ping with payload leaves state unchanged" do
      state = State.new(@test_opts)
      {:noreply, [], new_state} = Producer.handle_info({:gun_ws, nil, nil, {:ping, "x"}}, state)
      assert new_state == state
    end

    test "binary enqueues/dispatches explicitly" do
      bin = <<0, 1, 2>>

      # no demand → buffers
      {:noreply, [], st1} =
        Producer.handle_info({:gun_ws, nil, nil, {:binary, bin}}, State.new(@test_opts))

      assert st1.queue_size == 1

      # demand → dispatch
      st2 = %{State.new(@test_opts) | total_demand: 1}
      {:noreply, [^bin], st3} =
        Producer.handle_info({:gun_ws, nil, nil, {:binary, bin}}, st2)

      assert st3.queue_size == 0
    end
  end

  describe "handle_info(:gun_ws ... close*)" do
    setup do
      pid = self()

      :telemetry.attach(
        :disc_close,
        [:dummy_telemetry, :connection, :disconnected],
        fn _e, ms, md, _ -> send(pid, {:disc, ms, md}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(:disc_close) end)
      :ok
    end

    test ":close without payload clears conn and reconnects" do
      conn = self()
      state = %{State.new(@test_opts) | conn_pid: conn, ws_retry_opts: %{delay: 5, retries_left: 1, max_retries: 1}}

      capture =
        capture_log(fn ->
          {:noreply, [], new_state} =
            Producer.handle_info({:gun_ws, conn, :ref, :close}, state)

          assert new_state.conn_pid == nil
          assert new_state.stream_ref == nil
        end)

      assert capture =~ "websocket closed by peer"
      assert_receive {:disc, %{count: 1}, %{reason: :ws_close}}, 200
      assert_receive :connect, 200
    end

    test "{:close, payload} clears conn and reconnects" do
      conn = self()
      state = %{State.new(@test_opts) | conn_pid: conn, ws_retry_opts: %{delay: 5, retries_left: 1, max_retries: 1}}

      capture =
        capture_log(fn ->
          {:noreply, [], new_state} =
            Producer.handle_info({:gun_ws, conn, :ref, {:close, "bye"}}, state)

          assert new_state.conn_pid == nil
          assert new_state.stream_ref == nil
        end)

      assert capture =~ ~s|websocket closed: "bye"|
      assert_receive {:disc, %{count: 1}, %{reason: {:ws_close, "bye"}}}, 200
      assert_receive :connect, 200
    end

    test "{:close, code, reason} clears conn and reconnects" do
      conn = self()
      state = %{State.new(@test_opts) | conn_pid: conn, ws_retry_opts: %{delay: 5, retries_left: 1, max_retries: 1}}

      capture =
        capture_log(fn ->
          {:noreply, [], new_state} =
            Producer.handle_info({:gun_ws, conn, :ref, {:close, 4003, "connection unused"}}, state)

          assert new_state.conn_pid == nil
          assert new_state.stream_ref == nil
        end)

      assert capture =~ ~s|websocket closed: code=4003 reason="connection unused"|
      assert_receive {:disc, %{count: 1}, %{reason: {:ws_close, 4003, "connection unused"}}}, 200
      assert_receive :connect, 200
    end
  end

  describe "handle_info(:gun_error ...)" do
    setup do
      pid = self()

      :telemetry.attach(
        :fail_ws,
        [:dummy_telemetry, :connection, :failure],
        fn _e, ms, md, _ -> send(pid, {:failure, ms, md}) end,
        nil
      )

      on_exit(fn -> :telemetry.detach(:fail_ws) end)
      :ok
    end

    test "stream-level gun_error emits telemetry" do
      state = State.new(@test_opts)

      capture =
        capture_log(fn ->
          {:noreply, [], ^state} =
            Producer.handle_info({:gun_error, :conn, :ref, :econnreset}, state)
        end)

      assert capture =~ "gun stream error: :econnreset"
      assert_receive {:failure, %{count: 1}, %{reason: :econnreset}}, 200
    end

    test "connection-level gun_error emits telemetry" do
      state = State.new(@test_opts)

      capture =
        capture_log(fn ->
          {:noreply, [], ^state} =
            Producer.handle_info({:gun_error, :conn, :etimedout}, state)
        end)

      assert capture =~ "gun connection error: :etimedout"
      assert_receive {:failure, %{count: 1}, %{reason: :etimedout}}, 200
    end
  end

  describe "handle_info(:gun_down) (new variants)" do
    test "6-tuple gun_down handled like 5-tuple" do
      conn = self()
      state = %{State.new(@test_opts) | conn_pid: conn, ws_retry_opts: %{delay: 5, retries_left: 1, max_retries: 1}}

      capture =
        capture_log(fn ->
          {:noreply, [], new_state} =
            Producer.handle_info({:gun_down, conn, :ws, :normal, [], []}, state)

          assert new_state.conn_pid == nil
        end)

      assert capture =~ "connection lost: :normal"
      assert_receive :connect, 200
    end

    test "late gun_down for stale conn is ignored" do
      # state.conn_pid ≠ incoming conn; ensure we don't shutdown or schedule
      stale_conn = make_ref()
      state = %{State.new(@test_opts) | conn_pid: self()}

      :meck.new(:gun, [:non_strict])
      :meck.expect(:gun, :shutdown, fn _ -> flunk("shutdown should not be called for stale gun_down") end)

      capture =
        capture_log(fn ->
          {:noreply, [], ^state} =
            Producer.handle_info({:gun_down, stale_conn, :ws, :normal, []}, state)
        end)

      assert capture =~ "ignoring late gun_down for stale conn"
      refute_receive :connect, 100

      :meck.unload(:gun)
    end
  end
end
