defmodule OffBroadwayWebSocket.Handlers do
  @moduledoc false
  # Normalizes gun websocket frames to a small internal set
  # WITHOUT changing behavior.

  @type ws_msg :: {:data, binary()} | :ping | :pong | {:close, nil | term() | {non_neg_integer(), term()}}

  @spec normalize(term()) :: ws_msg
  def normalize({op, payload}) when op in [:text, :binary], do: {:data, payload}

  # Handle variants with payloads
  def normalize({:pong, _payload}), do: :pong
  def normalize({:ping, _payload}), do: :ping

  # No-payload shorthands
  def normalize(:ping), do: :ping
  def normalize(:pong), do: :pong

  # Close variants
  def normalize({:close, code, reason}), do: {:close, {code, reason}}
  def normalize({:close, payload}),      do: {:close, payload}
  def normalize(:close),                 do: {:close, nil}
end
