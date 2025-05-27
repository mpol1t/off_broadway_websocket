defmodule OffBroadwayWebSocket.Client do
  @moduledoc """
  Provides functions to establish and configure WebSocket connections
  using the **gun** library, with customizable timeouts and connection options.
  """

  @behaviour OffBroadwayWebSocket.ClientBehaviour

  @doc """
  Establishes a WebSocket connection to the specified URL and path with optional **gun** options,
  and customizable timeouts.

  ## Parameters
    - **url**: The base URL for the WebSocket connection (e.g., "wss://example.com").
    - **path**: The WebSocket path to upgrade to (e.g., "/ws").
    - **gun_opts**: A map containing :gun configuration.
    - **await_timeout**: The timeout in milliseconds to wait for the connection to become ready.
    - **connect_timeout**: The timeout in milliseconds for establishing the connection.

  ## Returns
    - **{:ok, %{conn_pid: pid(), stream_ref: reference()}}** on a successful connection and upgrade.
    - **{:error, reason}** if the connection or upgrade fails.
  """
  @spec connect(
          String.t(),
          String.t(),
          map(),
          non_neg_integer(),
          list()
        ) :: {:ok, map()} | {:error, term()}
  def connect(url, path, gun_opts, await_timeout, headers \\ []) do
    %URI{host: host, port: port, scheme: _scheme} = URI.parse(url)

    host = host || url

    with {:ok, conn_pid}  <- :gun.open(String.to_charlist(host), port, gun_opts),
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
end
