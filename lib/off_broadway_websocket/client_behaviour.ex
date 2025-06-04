defmodule OffBroadwayWebSocket.ClientBehaviour do
  @moduledoc """
  Behaviour describing the minimal client API used by the producer.

  Providing your own module that implements this behaviour allows swapping out
  the WebSocket implementation in tests or alternative transports.
  """

  @callback connect(
              url           :: String.t(),
              path          :: String.t(),
              gun_opts      :: map(),
              await_timeout :: non_neg_integer(),
              headers       :: [{String.t(), String.t()}]
            ) ::
            {:ok, %{conn_pid: pid(), stream_ref: reference()}} | {:error, term()}
end
