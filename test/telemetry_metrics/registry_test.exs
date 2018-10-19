defmodule Telemetry.Metrics.RegistryTest do
  use ExUnit.Case

  alias Telemetry.Metrics
  alias Telemetry.Metrics.Registry

  setup do
    registry = __MODULE__.TestRegistry

    on_exit fn ->
      case GenServer.whereis(registry) do
        nil ->
          :ok

        pid ->
          Process.exit(pid, :kill)
      end
    end

    {:ok, registry: registry}
  end

  describe "start_link/2" do
    test "raises when metric names are not unique", %{registry: registry} do
      definition1 = Metrics.new(:counter, [:my, :first, :event], name: [:metric])
      definition2 = Metrics.new(:counter, [:my, :second, :event], name: [:metric])

      assert_raise ArgumentError, fn ->
        Registry.start_link(registry, [definition1, definition2])
      end
    end
  end

  test "get_metric_names/1 returns the names of all registered metrics", %{registry: registry} do
    definition1 = Metrics.new(:counter, [:my, :first, :event], name: [:first, :metric])
    definition2 = Metrics.new(:counter, [:my, :second, :event], name: [:second, :metric])
    definition3 = Metrics.new(:counter, [:my, :third, :event], name: [:third, :metric])

    {:ok, _} = Registry.start_link(registry, [definition1, definition2, definition3])
    metric_names = Registry.get_metric_names(registry)

    assert 3 == length(metric_names)
    assert [:first, :metric] in metric_names
    assert [:second, :metric] in metric_names
    assert [:third, :metric] in metric_names
  end

  describe "collect/2" do
    test "returns error when metric with given name doesn't exist", %{registry: registry} do
      {:ok, _} = Registry.start_link(registry, [])

      assert {:error, :not_found} == Registry.collect(registry, [:metric])
    end

    test "returns datapoints produced by the metric", %{registry: registry} do
      metric_name = [:metric]
      metric = Metrics.new(:counter, [:my, :event], name: metric_name)

      {:ok, _} = Registry.start_link(registry, [metric])

      Telemetry.execute([:my, :event], 1)
      Telemetry.execute([:my, :event], 1)
      Telemetry.execute([:my, :event], 1)

      assert {:ok, [%{tagset: %{}, datapoints: %{count: 3}}]} == Registry.collect(registry, metric_name)
    end
  end
end
