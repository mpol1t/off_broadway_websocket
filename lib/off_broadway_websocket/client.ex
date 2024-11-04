defmodule OffBroadwayWebSocket.Client do
  @moduledoc """
  Provides functions to establish and configure WebSocket connections
  using the **gun** library, with customizable timeouts and connection options.
  """
  alias OffBroadwayWebSocket.Utils

  @doc """
  Establishes a WebSocket connection to the specified URL and path with optional **gun** options,
  and customizable timeouts.

  ## Parameters
    - **url**: The base URL for the WebSocket connection (e.g., "wss://example.com").
    - **path**: The WebSocket path to upgrade to (e.g., "/ws").
    - **gun_opts**: A tuple **{http_opts, ws_opts}** containing optional configurations for HTTP
      and WebSocket settings. Either **http_opts** or **ws_opts** may be **nil**.
    - **await_timeout**: The timeout in milliseconds to wait for the connection to become ready.
    - **connect_timeout**: The timeout in milliseconds for establishing the connection.

  ## Returns
    - **{:ok, %{conn_pid: pid(), stream_ref: reference()}}** on a successful connection and upgrade.
    - **{:error, reason}** if the connection or upgrade fails.
  """
  @spec connect(
          String.t(),
          String.t(),
          {map() | nil, map() | nil},
          non_neg_integer(),
          non_neg_integer()
        ) :: {:ok, map()} | {:error, term()}
  def connect(url, path, gun_opts, await_timeout, connect_timeout) do
    %URI{host: host, port: _port, scheme: scheme} = URI.parse(url)

    host    = host    || url
    scheme  = scheme  || "wss"

    opts = connect_opts(host, scheme, connect_timeout, gun_opts)

    with {:ok, conn_pid}  <- :gun.open(String.to_charlist(host), port(scheme), opts),
         {:ok, _protocol} <- :gun.await_up(conn_pid, await_timeout),
         stream_ref       <- :gun.ws_upgrade(conn_pid, path) do
      {:ok, %{conn_pid: conn_pid, stream_ref: stream_ref}}
    else
      {:error, reason} ->
        {:error, reason}
      other ->
        {:error, other}
    end
  end

  @doc false
  @spec connect_opts(String.t(), String.t(), non_neg_integer(), {map() | nil, map() | nil}) :: map()
  defp connect_opts(host, scheme, connect_timeout, {http_opts, ws_opts}) do
    opts = %{
      connect_timeout:  connect_timeout,
      retry:            0,
      protocols:        [:http],
      transport:        transport(scheme),
      tls_opts: [
        verify:         :verify_peer,
        cacertfile:     CAStore.file_path(),
        depth:          99,
        reuse_sessions: false,
        verify_fun:     {&:ssl_verify_hostname.verify_fun/3, [check_hostname: String.to_charlist(host)]}
      ]
    }

    opts
    |> Utils.put_with_nil(:http_opts,  http_opts)
    |> Utils.put_with_nil(:ws_opts,    ws_opts)
  end

  @doc false
  @spec transport(String.t()) :: atom()
  defp transport("wss"),  do: :tls
  defp transport(_),      do: :tcp

  @doc false
  @spec port(String.t()) :: non_neg_integer()
  defp port("wss"), do: 443
  defp port("ws"),  do: 80
  defp port(_),     do: 443
end