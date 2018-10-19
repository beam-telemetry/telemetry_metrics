defmodule Telemetry.Metrics.Metric.Counter do
  @moduledoc """
  Metric counting how many times the event has been emitted.

  This metric collects only a single datapoint called `:count`.
  """

  @behaviour Telemetry.Metrics.Metric

  ## WARNING: really dumb now, just to make the tests pass
  def init(_opts) do
    {:ok, pid} = Agent.start_link(fn -> %{} end)
    {:ok, %{pid: pid}}
  end

  def update(_event_value, tagset, state) do
    Agent.update(state.pid, fn values_by_tagset ->
      Map.update(values_by_tagset, tagset, 1, &(&1 + 1))
    end)

    state
  end

  def collect(state) do
    state.pid
    |> Agent.get(& &1)
    |> Enum.map(fn {tagset, value} ->
      %{
        tagset: tagset,
        datapoints: %{
          count: value
        }
      }
    end)
  end
end
