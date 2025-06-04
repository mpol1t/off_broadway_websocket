defmodule OffBroadwayWebSocket.ClientTest do
  use ExUnit.Case, async: true

  alias OffBroadwayWebSocket.Client

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
end
