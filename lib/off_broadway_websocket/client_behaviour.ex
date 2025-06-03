defmodule OffBroadwayWebSocket.ClientBehaviour do
  @moduledoc false

  @callback connect(
              url           :: String.t(),
              path          :: String.t(),
              gun_opts      :: map(),
              await_timeout :: non_neg_integer(),
              headers       :: [{String.t(), String.t()}]
            ) ::
            {:ok, %{conn_pid: pid(), stream_ref: reference()}} | {:error, term()}
end
