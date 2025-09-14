defmodule OffBroadwayWebSocket.Telemetry do
  @moduledoc false
  # Small helpers in case you want to evolve metadata later.

  def ok(state, meta \\ %{}) do
    :telemetry.execute([state.telemetry_id, :connection, :success], %{count: 1}, meta)
  end

  def success(state) do
    :telemetry.execute([state.telemetry_id, :connection, :success], %{count: 1}, %{url: state.url <> state.path})
  end

  def fail(state, reason) do
    :telemetry.execute([state.telemetry_id, :connection, :failure], %{count: 1}, %{reason: reason})
  end

  def disconnected(state, reason) do
    :telemetry.execute([state.telemetry_id, :connection, :disconnected], %{count: 1}, %{reason: reason})
  end

  def timeout(state) do
    :telemetry.execute([state.telemetry_id, :connection, :timeout], %{count: 1}, %{})
  end

  def status(state, value) do
    :telemetry.execute([state.telemetry_id, :connection, :status], %{value: value}, %{})
  end
end
