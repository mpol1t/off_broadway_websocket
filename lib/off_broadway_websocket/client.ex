defmodule OffBroadwayWebSocket.Client do
  @moduledoc """
  Provides functions to establish and configure WebSocket connections
  using the **gun** library, with customizable timeouts and connection options.
  """

  @behaviour OffBroadwayWebSocket.ClientBehaviour

  @doc """
  Establishes a WebSocket connection using `:gun`.

  The `gun_opts` map is forwarded directly to `:gun.open/3` so TLS, HTTP and
  WebSocket options can be configured as required. The call waits up to
  `await_timeout` milliseconds for `:gun.await_up/2` to succeed before returning
  an error. Additional upgrade headers may be supplied via `headers`.

  ## Parameters
    - **url**: The base URL for the WebSocket connection (e.g., "wss://example.com").
    - **path**: The WebSocket path to upgrade to (e.g., "/ws").
    - **gun_opts**: Options passed to `:gun.open/3`.
    - **await_timeout**: How long to wait for the connection to become ready.
    - **headers**: Optional headers for the WebSocket upgrade.

  ## Returns
    - **{:ok, %{conn_pid: pid(), stream_ref: reference()}}** on a successful connection and upgrade.
    - **{:error, reason}** if the connection or upgrade fails.
  """
  @spec connect(
          url :: String.t(),
          path :: String.t(),
          gun_opts :: map(),
          await_timeout :: non_neg_integer(),
          headers :: [{String.t(), String.t()}]
        ) ::
        {:ok, %{conn_pid: pid(), stream_ref: reference()}} | {:error, term()}
  def connect(url, path, gun_opts, await_timeout, headers \\ []) do
    uri = URI.parse(url)
    host = uri.host || url
    port = uri.port || default_port(uri)

    with {:ok, conn_pid}  <- :gun.open(to_charlist(host), port, gun_opts),
         {:ok, _protocol} <- :gun.await_up(conn_pid, await_timeout) do
      stream_ref = :gun.ws_upgrade(conn_pid, path, headers)
      {:ok, %{conn_pid: conn_pid, stream_ref: stream_ref}}
    else
      {:error, reason} ->
        {:error, reason}

      other ->
        {:error, other}
    end
  end

  defp default_port(%URI{scheme: scheme}) when scheme in ["wss", "https"], do: 443
  defp default_port(_), do: 80
end
