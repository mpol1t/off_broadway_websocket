defmodule OffBroadwayWebSocket.ClientBehaviour do
  @moduledoc false

  @callback connect(
              url :: String.t(),
              path :: String.t(),
              gun_opts :: map(),
              await_timeout :: non_neg_integer(),
              headers :: list()
            ) :: {:ok, map()} | {:error, any()}
end
