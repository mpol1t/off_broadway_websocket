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
    test "shutdown and telemetry" do
      conn = self()
      pid = self()

      :telemetry.attach(
        :disc,
        [:dummy_telemetry, :connection, :disconnected],
        fn _e, ms, md, _ -> send(pid, {:disc, ms, md}) end,
        nil
      )

      :meck.new(:gun, [:non_strict])

      :meck.expect(:gun, :shutdown, fn ^conn ->
        send(pid, :down)
        :ok
      end)

      capture =
        capture_log(fn ->
          {:noreply, [], new_state} =
            Producer.handle_info(
              {:gun_down, conn, :proto, :reason, []},
              %{State.new(@test_opts) | conn_pid: conn}
            )

          assert new_state.conn_pid == nil
        end)

      assert capture =~ "connection lost"
      assert_receive :down, 500
      assert_receive {:disc, %{count: 1}, %{reason: :reason}}, 500

      :meck.unload(:gun)
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
end
