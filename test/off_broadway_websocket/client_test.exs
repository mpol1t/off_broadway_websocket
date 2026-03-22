defmodule OffBroadwayWebSocket.ClientTest do
  use ExUnit.Case, async: true

  alias OffBroadwayWebSocket.Client
  alias OffBroadwayWebSocket.State

  defmodule ConnectOnceClient do
    @behaviour OffBroadwayWebSocket.ClientBehaviour

    @impl true
    def connect(_url, _path, _gun_opts, _await_timeout, headers) do
      send(Process.get(:test_pid), {:connect_headers, headers})
      {:ok, %{conn_pid: :pid, stream_ref: :ref}}
    end
  end

  describe "connect/5" do
    test "successful connection" do
      url = "wss://example.com"
      path = "/v1/test-endpoint"
      gun_opts = %{foo: :bar}
      await_timeout = 50
      headers = [{"authorization", "token"}]
      expected_port = 443

      :meck.new(:gun, [:non_strict])

      :meck.expect(:gun, :open, fn host_charlist, port, opts ->
        assert host_charlist == ~c"example.com"
        assert port == expected_port
        assert opts == gun_opts
        {:ok, :dummy_conn_pid}
      end)

      :meck.expect(:gun, :await_up, fn conn_pid, timeout ->
        assert conn_pid == :dummy_conn_pid
        assert timeout == await_timeout
        {:ok, :dummy_protocol}
      end)

      :meck.expect(:gun, :ws_upgrade, fn conn_pid, upgrade_path, upgrade_headers ->
        assert conn_pid == :dummy_conn_pid
        assert upgrade_path == path
        assert upgrade_headers == headers
        :dummy_stream_ref
      end)

      assert {:ok, %{conn_pid: :dummy_conn_pid, stream_ref: :dummy_stream_ref}} =
               Client.connect(url, path, gun_opts, await_timeout, headers)

      assert :meck.num_calls(:gun, :open, 1)
      assert :meck.num_calls(:gun, :await_up, 1)
      assert :meck.num_calls(:gun, :ws_upgrade, 1)

      :meck.unload(:gun)
    end

    test "fails when :gun.open returns an error" do
      url = "wss://example.com"
      path = "/v1/test-endpoint"
      gun_opts = %{}
      await_timeout = 50
      headers = []

      :meck.new(:gun, [:non_strict])

      :meck.expect(:gun, :open, fn _host, _port, _opts ->
        {:error, :dummy_reason}
      end)

      assert {:error, :dummy_reason} =
               Client.connect(url, path, gun_opts, await_timeout, headers)

      assert :meck.num_calls(:gun, :open, 1)
      :meck.unload(:gun)
    end

    test "uses default port 443 for https" do
      url = "https://example.com"
      path = "/v1/test-endpoint"
      gun_opts = %{}
      await_timeout = 50

      :meck.new(:gun, [:non_strict])

      :meck.expect(:gun, :open, fn host_charlist, port, opts ->
        assert host_charlist == ~c"example.com"
        assert port == 443
        assert opts == gun_opts
        {:error, :fail}
      end)

      assert {:error, :fail} = Client.connect(url, path, gun_opts, await_timeout, [])

      assert :meck.num_calls(:gun, :open, 1)
      :meck.unload(:gun)
    end

    test "falls back to url as host when host is missing" do
      url = "example.com"
      path = "/v1/test-endpoint"
      gun_opts = %{}
      await_timeout = 50

      :meck.new(:gun, [:non_strict])

      :meck.expect(:gun, :open, fn host_charlist, port, opts ->
        assert host_charlist == ~c"example.com"
        assert port == 80
        assert opts == gun_opts
        {:error, :fail}
      end)

      assert {:error, :fail} = Client.connect(url, path, gun_opts, await_timeout, [])

      assert :meck.num_calls(:gun, :open, 1)
      :meck.unload(:gun)
    end

    test "fails when :gun.await_up returns an error" do
      url = "wss://example.com"
      path = "/v1/test-endpoint"
      gun_opts = %{}
      await_timeout = 50
      headers = []

      :meck.new(:gun, [:non_strict])

      :meck.expect(:gun, :open, fn _host, _port, _opts ->
        {:ok, :dummy_conn_pid}
      end)

      :meck.expect(:gun, :await_up, fn _conn_pid, _timeout ->
        {:error, :dummy_reason}
      end)

      assert {:error, :dummy_reason} =
               Client.connect(url, path, gun_opts, await_timeout, headers)

      assert :meck.num_calls(:gun, :open, 1)
      assert :meck.num_calls(:gun, :await_up, 1)

      :meck.unload(:gun)
    end

    test "uses default port when none provided" do
      url = "ws://example.com"
      path = "/v1/test-endpoint"
      gun_opts = %{}
      await_timeout = 50

      :meck.new(:gun, [:non_strict])

      :meck.expect(:gun, :open, fn host_charlist, port, opts ->
        assert host_charlist == ~c"example.com"
        assert port == 80
        assert opts == gun_opts
        {:error, :fail}
      end)

      assert {:error, :fail} = Client.connect(url, path, gun_opts, await_timeout, [])

      assert :meck.num_calls(:gun, :open, 1)
      :meck.unload(:gun)
    end
  end

  describe "connect_once/1" do
    setup do
      original_client = Application.get_env(:off_broadway_websocket, :client)
      on_exit(fn -> Application.put_env(:off_broadway_websocket, :client, original_client) end)
      :ok
    end

    test "uses headers_fn result when provided" do
      test_pid = self()

      Process.put(:test_pid, test_pid)
      on_exit(fn -> Process.delete(:test_pid) end)
      Application.put_env(:off_broadway_websocket, :client, ConnectOnceClient)

      state =
        State.new(
          url: "wss://example.com",
          path: "/socket",
          headers: [{"authorization", "stale"}],
          headers_fn: fn -> [{"authorization", "fresh"}] end
        )

      assert {:ok, %{conn_pid: :pid, stream_ref: :ref}} = Client.connect_once(state)
      assert_receive {:connect_headers, [{"authorization", "fresh"}]}
    end

    test "returns typed error when headers_fn raises" do
      state =
        State.new(
          url: "wss://example.com",
          path: "/socket",
          headers_fn: fn -> raise "boom" end
        )

      assert {:error, {:headers_fn_exception, %RuntimeError{message: "boom"}}} =
               Client.connect_once(state)
    end
  end
end
