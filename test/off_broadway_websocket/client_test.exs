defmodule OffBroadwayWebSocket.ClientTest do
  use ExUnit.Case, async: true

  alias OffBroadwayWebSocket.Client

  describe "connect/6" do
    test "successful connection" do
      dummy_host = "wss://example.com"
      dummy_path = "/v1/test-endpoint"

      opts = Client.connect_opts("example.com", "wss", 50, {nil, nil})

      :meck.new(:gun, [:non_strict])

      :meck.expect(:gun, :open, fn _host, _port, _opts -> {:ok, :dummy_conn_pid} end)
      :meck.expect(:gun, :await_up, fn _conn_pid, _await_timeout -> {:ok, :dummy_protocol} end)
      :meck.expect(:gun, :ws_upgrade, fn _conn_pid, _path, _headers -> :dummy_stream_ref end)

      assert {:ok, %{conn_pid: :dummy_conn_pid, stream_ref: :dummy_stream_ref}} =
               Client.connect(
                 dummy_host,
                 dummy_path,
                 {nil, nil},
                 50,
                 50
               )

      assert :meck.num_calls(:gun, :open, [~c"example.com", 443, opts]) == 1
      assert :meck.num_calls(:gun, :await_up, [:dummy_conn_pid, 50]) == 1
      assert :meck.num_calls(:gun, :ws_upgrade, [:dummy_conn_pid, dummy_path, []]) == 1

      :meck.unload(:gun)
    end

    test "fails when :gun.open returns an error" do
      dummy_host = "wss://example.com"
      dummy_path = "/v1/test-endpoint"

      opts = Client.connect_opts("example.com", "wss", 50, {nil, nil})

      :meck.new(:gun, [:non_strict])

      :meck.expect(:gun, :open, fn _host, _port, _opts -> {:error, :dummy_reason} end)

      assert {:error, :dummy_reason} = Client.connect(dummy_host, dummy_path, {nil, nil}, 50, 50)

      assert :meck.num_calls(:gun, :open, [~c"example.com", 443, opts]) == 1

      :meck.unload(:gun)
    end

    test "fails when :gun.await_up returns an error" do
      dummy_host = "wss://example.com"
      dummy_path = "/v1/test-endpoint"

      opts = Client.connect_opts("example.com", "wss", 50, {nil, nil})

      :meck.new(:gun, [:non_strict])

      :meck.expect(:gun, :open, fn _host, _port, _opts -> {:ok, :dummy_conn_pid} end)
      :meck.expect(:gun, :await_up, fn _conn_pid, _await_timeout -> {:error, :dummy_reason} end)

      assert {:error, :dummy_reason} = Client.connect(dummy_host, dummy_path, {nil, nil}, 50, 50)

      assert :meck.num_calls(:gun, :open, [~c"example.com", 443, opts]) == 1
      assert :meck.num_calls(:gun, :await_up, [:dummy_conn_pid, 50]) == 1

      :meck.unload(:gun)
    end
  end

  describe "transport/1" do
    test "returns :tls when passed wss string" do
      assert :tls == Client.transport("wss")
    end

    test "defaults to :tcp when not using wss string" do
      assert :tcp == Client.transport("ws")
    end
  end

  describe "port/1" do
    test "returns port no 443 when using secure websocket" do
      assert 443 == Client.port("wss")
    end

    test "returns port no 80 when not using secure websocket" do
      assert 80 == Client.port("ws")
    end

    test "defaults to port no 443 when passed unrecognized protocol" do
      assert 443 == Client.port("http")
    end
  end

  describe "connect_opts/4" do
    test "builds opts with given host, scheme, and timeout" do
      host = "example.com"
      scheme = "wss"
      connect_timeout = 5000
      http_opts = %{some: "option"}
      ws_opts = %{another: "option"}

      opts = Client.connect_opts(host, scheme, connect_timeout, {http_opts, ws_opts})

      assert opts.connect_timeout == connect_timeout
      assert opts.retry == 0
      assert opts.protocols == [:http]
      assert opts.transport == :tls
      assert is_list(opts.tls_opts)
      assert {fun, config} = Keyword.fetch!(opts.tls_opts, :verify_fun)
      assert is_function(fun, 3)
      assert [check_hostname: check_hostname] = config
      assert check_hostname == String.to_charlist(host)
      assert opts.http_opts == http_opts
      assert opts.ws_opts == ws_opts
    end
  end
end
