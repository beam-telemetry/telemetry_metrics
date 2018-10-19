defmodule Telemetry.Metrics.Metric.CounterTest do
  use ExUnit.Case

  import Telemetry.Metrics.TestHelpers

  alias Telemetry.Metrics.Metric.Counter

  test "counts the number of updates grouped by tagset" do
    {:ok, state} = Counter.init([])

    Counter.update(20, %{table: "users", kind: "select"}, state)
    Counter.update(-2, %{table: "users", kind: "select"}, state)
    Counter.update(17, %{table: "users", kind: "insert"}, state)
    Counter.update(30, %{table: "products", kind: "delete"}, state)
    Counter.update(21, %{}, state)

    measurements = Counter.collect(state)

    assert 4 == length(measurements)
    assert 2 == find_datapoint(measurements, :count, %{table: "users", kind: "select"})
    assert 1 == find_datapoint(measurements, :count, %{table: "users", kind: "insert"})
    assert 1 == find_datapoint(measurements, :count, %{table: "products", kind: "delete"})
    assert 1 == find_datapoint(measurements, :count, %{})
  end

  test "produces a single datapoint" do
    {:ok, state} = Counter.init([])

    Counter.update(1, %{}, state)

    assert [%{datapoints: datapoints}] = Counter.collect(state)
    assert [:count] = Map.keys(datapoints)
  end
end
