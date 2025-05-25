# defmodule OffBroadwayWebSocket.ProducerTest do
#  use ExUnit.Case, async: false
#
#  import ExUnit.CaptureLog
#  import Mox
#
#  alias OffBroadwayWebSocket.Producer
#  alias OffBroadwayWebSocket.State
#
#  @test_opts [
#    broadway: [
#      processors: [
#        default: [
#          min_demand: 0,
#          max_demand: 100,
#          concurrency: 2
#        ]
#      ]
#    ],
#    url: "wss://api.test.com",
#    path: "/v1/test-endpoint",
#    ws_timeout: 30_000,
#    ws_opts: %{
#      keepalive: 15_000,
#      silence_pings: false
#    },
#    http_opts: %{
#      version: :"HTTP/1.1"
#    },
#    telemetry_id: :dummy_telemetry
#  ]
#
#  setup :set_mox_from_context
#  setup :verify_on_exit!
#
#  describe "init/1" do
#    test "successful connection" do
#      OffBroadwayWebSocket.MockClient
#      |> expect(:connect, fn _url, _path, _opts, _await_timeout, _connect_timeout, _headers ->
#        {:ok, %{conn_pid: :fake_pid, stream_ref: :fake_ref}}
#      end)
#
#      assert capture_log(fn ->
#               {:ok, pid} = Producer.start_link(@test_opts)
#
#               %GenStage{state: state} = :sys.get_state(pid)
#               assert state.conn_pid == :fake_pid
#               assert state.stream_ref == :fake_ref
#             end) =~ "Connected successfully to wss://api.test.com/v1/test-endpoint"
#    end
#
#    test "failed connection" do
#      Process.flag(:trap_exit, true)
#
#      test_pid = self()
#
#      handler_id = :test_connection_failure_handler
#
#      :telemetry.attach(
#        handler_id,
#        [:dummy_telemetry, :connection, :failure],
#        fn event, measurements, metadata, _config ->
#          send(test_pid, {event, measurements, metadata})
#        end,
#        nil
#      )
#
#      OffBroadwayWebSocket.MockClient
#      |> expect(:connect, fn _url, _path, _opts, _await_timeout, _connect_timeout, _headers ->
#        {:error, :dummy_reason}
#      end)
#
#      assert capture_log(fn ->
#               assert {:error, :dummy_reason} = Producer.start_link(@test_opts)
#             end) =~ "Failed to connect: :dummy_reason"
#
#      assert_receive {[:dummy_telemetry, :connection, :failure], %{count: 1},
#                      %{reason: :dummy_reason}},
#                     1000
#
#      :telemetry.detach(handler_id)
#    end
#  end
#
#  describe "handle_info/2 for :gun_upgrade" do
#    test "updates state and schedules timeout when ws_timeout is set" do
#      test_pid = self()
#      conn_pid = self()
#
#      state = %State{State.new(@test_opts) | ws_timeout: 50, pid: test_pid}
#
#      success_handler_id = :test_connection_success_handler
#      status_handler_id = :test_connection_status_handler
#
#      :telemetry.attach(
#        success_handler_id,
#        [:dummy_telemetry, :connection, :success],
#        fn event, measurements, metadata, _config ->
#          send(test_pid, {event, measurements, metadata})
#        end,
#        nil
#      )
#
#      :telemetry.attach(
#        status_handler_id,
#        [:dummy_telemetry, :connection, :status],
#        fn event, measurements, metadata, _config ->
#          send(test_pid, {event, measurements, metadata})
#        end,
#        nil
#      )
#
#      assert capture_log(fn ->
#               assert {:noreply, [], %State{conn_pid: ^conn_pid, stream_ref: :dummy_stream_ref}} =
#                        Producer.handle_info(
#                          {:gun_upgrade, conn_pid, :dummy_stream_ref, ["websocket"], nil},
#                          state
#                        )
#             end) =~ ~r/First timeout check scheduled in 0.05s*/
#
#      assert_receive {[:dummy_telemetry, :connection, :success], %{count: 1},
#                      %{url: "wss://api.test.com/v1/test-endpoint"}},
#                     1000
#
#      assert_receive {[:dummy_telemetry, :connection, :status], %{value: 1}, %{}}, 1000
#      assert_receive :check_ws_timeout, 100
#
#      :telemetry.detach(success_handler_id)
#      :telemetry.detach(status_handler_id)
#    end
#
#    test "updates state without scheduling timeout when ws_timeout is nil" do
#      test_pid = self()
#      conn_pid = self()
#
#      state = %State{State.new(@test_opts) | ws_timeout: nil, pid: test_pid}
#
#      success_handler_id = :test_connection_success_handler
#      status_handler_id = :test_connection_status_handler
#
#      :telemetry.attach(
#        success_handler_id,
#        [:dummy_telemetry, :connection, :success],
#        fn event, measurements, metadata, _config ->
#          send(test_pid, {event, measurements, metadata})
#        end,
#        nil
#      )
#
#      :telemetry.attach(
#        status_handler_id,
#        [:dummy_telemetry, :connection, :status],
#        fn event, measurements, metadata, _config ->
#          send(test_pid, {event, measurements, metadata})
#        end,
#        nil
#      )
#
#      assert capture_log(fn ->
#               assert {:noreply, [], %State{conn_pid: ^conn_pid, stream_ref: :dummy_stream_ref}} =
#                        Producer.handle_info(
#                          {:gun_upgrade, conn_pid, :dummy_stream_ref, ["websocket"], nil},
#                          state
#                        )
#             end) =~ "WebSocket upgrade message received."
#
#      assert_receive {[:dummy_telemetry, :connection, :success], %{count: 1},
#                      %{url: "wss://api.test.com/v1/test-endpoint"}},
#                     1000
#
#      assert_receive {[:dummy_telemetry, :connection, :status], %{value: 1}, %{}}, 1000
#      refute_received :check_ws_timeout
#
#      :telemetry.detach(success_handler_id)
#      :telemetry.detach(status_handler_id)
#    end
#  end
#
#  describe "handle_info/2 for :gun_response and :gun_data" do
#    test "ignores gun_response messages" do
#      state = State.new(@test_opts)
#
#      assert {:noreply, [], ^state} =
#               Producer.handle_info({:gun_response, nil, nil, nil, nil, nil}, state)
#    end
#
#    test "ignores gun_data messages" do
#      state = State.new(@test_opts)
#
#      assert {:noreply, [], ^state} = Producer.handle_info({:gun_data, nil, nil, nil, nil}, state)
#    end
#  end
#
#  describe "handle_info/2 for gun_ws messages" do
#    test "updates last_pong on receiving :pong" do
#      assert {:noreply, [], state} =
#               Producer.handle_info({:gun_ws, nil, nil, :pong}, State.new(@test_opts))
#
#      assert DateTime.before?(state.last_pong, DateTime.utc_now())
#    end
#
#    test "handles :ping without state change" do
#      state = State.new(@test_opts)
#
#      assert {:noreply, [], new_state} = Producer.handle_info({:gun_ws, nil, nil, :ping}, state)
#      assert new_state == state
#    end
#
#    test "enqueues message for other gun_ws events and doesn't dispatch when demand is zero" do
#      msg = "dummy message"
#
#      assert {:noreply, [], state} =
#               Producer.handle_info({:gun_ws, nil, nil, {:text, msg}}, State.new(@test_opts))
#
#      assert state.queue_size == 1
#      assert :queue.len(state.message_queue) == 1
#      assert :queue.head(state.message_queue) == msg
#    end
#
#    test "enqueues message for other gun_ws events and dispatch for non zero demand" do
#      msg = "dummy message"
#
#      # use non zero demand to dispatch the event
#      state = %State{State.new(@test_opts) | total_demand: 10}
#
#      assert {:noreply, [^msg], new_state} =
#               Producer.handle_info({:gun_ws, nil, nil, {:text, msg}}, state)
#
#      assert new_state.queue_size == 0
#      assert :queue.len(new_state.message_queue) == 0
#    end
#  end
#
#  describe "handle_info/2 for :gun_down" do
#    test "logs error, executes telemetry, closes connection and stops process" do
#      state = State.new(@test_opts)
#
#      conn_pid = self()
#      test_pid = self()
#
#      handler_id = :test_connection_failure_handler
#
#      :telemetry.attach(
#        handler_id,
#        [:dummy_telemetry, :connection, :disconnected],
#        fn event, measurements, metadata, _config ->
#          send(test_pid, {event, measurements, metadata})
#        end,
#        nil
#      )
#
#      :meck.new(:gun, [:non_strict])
#
#      :meck.expect(:gun, :close, fn ^conn_pid ->
#        send(self(), {:gun_close_called, conn_pid})
#        :ok
#      end)
#
#      assert capture_log(fn ->
#               assert {:stop, {:error, :dummy_reason}, ^state} =
#                        Producer.handle_info(
#                          {:gun_down, conn_pid, :protocol, :dummy_reason, :killed_streams},
#                          state
#                        )
#             end) =~ "Connection lost: :dummy_reason"
#
#      assert_receive {:gun_close_called, ^conn_pid}, 1000
#      assert :meck.num_calls(:gun, :close, [conn_pid]) == 1
#
#      assert_receive {[:dummy_telemetry, :connection, :disconnected], %{count: 1},
#                      %{reason: :dummy_reason}},
#                     1000
#
#      :meck.unload(:gun)
#      :telemetry.detach(handler_id)
#    end
#  end
#
#  describe "handle_info/2 for :check_ws_timeout" do
#    test "triggers timeout when last_pong is nil or outdated" do
#      conn_pid = self()
#      test_pid = self()
#
#      state = %State{State.new(@test_opts) | conn_pid: conn_pid, pid: test_pid}
#
#      handler_id = :test_websocket_timeout_handler
#
#      :telemetry.attach(
#        handler_id,
#        [:dummy_telemetry, :connection, :timeout],
#        fn event, measurements, metadata, _config ->
#          send(test_pid, {event, measurements, metadata})
#        end,
#        nil
#      )
#
#      :meck.new(:gun, [:non_strict])
#
#      :meck.expect(:gun, :close, fn ^conn_pid ->
#        send(self(), {:gun_close_called, conn_pid})
#        :ok
#      end)
#
#      assert capture_log(fn ->
#               assert {:stop, {:error, :timeout}, ^state} =
#                        Producer.handle_info(:check_ws_timeout, state)
#             end) =~ "Ping/Pong timeout. Closing connection..."
#
#      assert_receive {:gun_close_called, ^conn_pid}, 1000
#      assert :meck.num_calls(:gun, :close, [conn_pid]) == 1
#      assert_receive {[:dummy_telemetry, :connection, :timeout], %{count: 1}, %{}}, 1000
#
#      :meck.unload(:gun)
#      :telemetry.detach(handler_id)
#    end
#
#    test "reschedules timeout when last_pong is recent" do
#      test_pid = self()
#
#      state = %State{
#        State.new(@test_opts)
#        | last_pong: DateTime.utc_now(),
#          ws_timeout: 50,
#          pid: test_pid
#      }
#
#      assert {:noreply, [], ^state} = Producer.handle_info(:check_ws_timeout, state)
#      assert_receive :check_ws_timeout, 100
#    end
#  end
#
#  describe "handle_demand/2 and dispatch_events/2" do
#    test "dispatches events when queue_size is sufficient" do
#      events = [1, 2, 3, 4, 5]
#      incoming_demand = 3
#
#      state = %State{
#        State.new(@test_opts)
#        | message_queue: :queue.from_list(events),
#          queue_size: Kernel.length(events)
#      }
#
#      {response, dispatched_events, new_state} = Producer.handle_demand(incoming_demand, state)
#
#      assert response == :noreply
#      assert dispatched_events == Enum.take(events, incoming_demand)
#      assert new_state.message_queue == :queue.from_list(Enum.drop(events, incoming_demand))
#      assert new_state.queue_size == Kernel.length(events) - incoming_demand
#      assert new_state.total_demand == incoming_demand - Kernel.length(dispatched_events)
#    end
#
#    test "accumulates demand when queue_size is insufficient" do
#      events = [1, 2, 3, 4, 5]
#      incoming_demand = 3
#
#      state = %State{
#        State.new(@test_opts)
#        | message_queue: :queue.from_list(events),
#          queue_size: Kernel.length(events),
#          min_demand: 10
#      }
#
#      {response, dispatched_events, new_state} = Producer.handle_demand(incoming_demand, state)
#
#      assert response == :noreply
#      assert dispatched_events == []
#      assert new_state.message_queue == :queue.from_list(events)
#      assert new_state.queue_size == Kernel.length(events)
#      assert new_state.total_demand == incoming_demand
#    end
#  end
#
#  describe "terminate/2" do
#    test "closes connection if conn_pid exists" do
#      conn_pid = self()
#      test_pid = self()
#
#      state = %State{State.new(@test_opts) | conn_pid: conn_pid}
#
#      handler_id = :test_connection_failure_handler
#
#      :telemetry.attach(
#        handler_id,
#        [:dummy_telemetry, :connection, :status],
#        fn event, measurements, metadata, _config ->
#          send(test_pid, {event, measurements, metadata})
#        end,
#        nil
#      )
#
#      :meck.new(:gun, [:non_strict])
#
#      :meck.expect(:gun, :close, fn ^conn_pid ->
#        send(self(), {:gun_close_called, conn_pid})
#        :ok
#      end)
#
#      assert capture_log(fn ->
#               assert :ok = Producer.terminate(:dummy_reason, state)
#             end) =~ "Connection closed."
#
#      assert_receive {:gun_close_called, ^conn_pid}, 1000
#      assert :meck.num_calls(:gun, :close, [conn_pid]) == 1
#      assert_receive {[:dummy_telemetry, :connection, :status], %{value: 0}, %{}}, 1000
#
#      :meck.unload(:gun)
#      :telemetry.detach(handler_id)
#    end
#
#    test "does nothing if conn_pid is nil" do
#      conn_pid = self()
#      test_pid = self()
#
#      state = State.new(@test_opts)
#
#      handler_id = :test_connection_failure_handler
#
#      :telemetry.attach(
#        handler_id,
#        [:dummy_telemetry, :connection, :status],
#        fn event, measurements, metadata, _config ->
#          send(test_pid, {event, measurements, metadata})
#        end,
#        nil
#      )
#
#      :meck.new(:gun, [:non_strict])
#
#      :meck.expect(:gun, :close, fn ^conn_pid ->
#        send(self(), {:gun_close_called, conn_pid})
#        :ok
#      end)
#
#      assert capture_log(fn ->
#               assert :ok = Producer.terminate(:dummy_reason, state)
#             end) =~ "Connection closed."
#
#      assert :meck.num_calls(:gun, :close, [conn_pid]) == 0
#      assert_receive {[:dummy_telemetry, :connection, :status], %{value: 0}, %{}}, 1000
#
#      :meck.unload(:gun)
#      :telemetry.detach(handler_id)
#    end
#  end
# end

defmodule OffBroadwayWebSocket.ProducerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mox

  alias OffBroadwayWebSocket.Producer
  alias OffBroadwayWebSocket.State
  alias GenStage

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
      OffBroadwayWebSocket.MockClient
      |> expect(:connect, fn _url, _path, _opts, _await, _headers ->
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

      OffBroadwayWebSocket.MockClient
      |> expect(:connect, fn _url, _path, _opts, _await, _headers ->
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
      state = %State{State.new(@test_opts) | ws_timeout: 100, pid: self()}

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
      state = %State{State.new(@test_opts) | ws_timeout: nil, pid: self()}

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
      state = %State{State.new(@test_opts) | total_demand: 1}

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
              %State{State.new(@test_opts) | conn_pid: conn}
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
      state = %State{State.new(@test_opts) | conn_pid: conn, pid: conn, ws_timeout: 1}

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
      state = %State{
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
      state = %State{
        State.new(@test_opts)
        | message_queue: :queue.from_list([1, 2]),
          queue_size: 2
      }

      assert {:noreply, [1], new_state} = Producer.handle_demand(1, state)
      assert new_state.queue_size == 1
    end

    test "queues demand when insufficient" do
      state = %State{
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
          assert :ok = Producer.terminate(:reason, %State{State.new(@test_opts) | conn_pid: conn})
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
