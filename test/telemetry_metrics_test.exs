defmodule Telemetry.MetricsTest do
  use ExUnit.Case

  import Telemetry.Metrics.TestHelpers

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

  test "metric value is updated", %{registry: registry} do
    event_name = [:http, :request, :count]
    metric_name = event_name

    metrics = [
      Metrics.new(
        :counter,
        event_name,
        # by default these keys are retrieved from event metadata
        tags: [:controller, :action]
      )
    ]

    {:ok, _} = Registry.start_link(registry, metrics)

    Telemetry.execute(event_name, 1, %{controller: "user_controller", action: "get"})
    Telemetry.execute(event_name, 1, %{controller: "user_controller", action: "get"})
    Telemetry.execute(event_name, 1, %{controller: "user_controller", action: "create"})

    {:ok, measurements} = Registry.collect(registry, metric_name)

    assert 2 == length(measurements)

    assert 2 ==
             find_datapoint(measurements, :count, %{controller: "user_controller", action: "get"})

    assert 1 ==
             find_datapoint(measurements, :count, %{
               controller: "user_controller",
               action: "create"
             })
  end

  describe "new/2,3" do
    test "raises an error on unknown metric type" do
      assert_raise ArgumentError, fn ->
        Metrics.new(:meter, [:http, :request, :count])
      end
    end

    test "sets a metric name in the definition to be equal to event name by default" do
      event_name = [:http, :request, :count]

      definition = Metrics.new(:counter, event_name)

      assert event_name == definition.metric_name
    end

    test "sets tags in the definition to be empty list by default" do
      definition = Metrics.new(:counter, [:http, :request, :count])

      assert [] == definition.tags
    end

    test "raises an error when metric name is not a list of atoms" do
      assert_raise ArgumentError, fn ->
        Metrics.new(:counter, [:http, :request, :count], name: :my_metric)
      end
    end

    test "raises an error when event name is not a list of atoms" do
      assert_raise ArgumentError, fn ->
        Metrics.new(:counter, :my_event, name: [:http, :request, :count])
      end
    end

    test "raises an error when tags is not a list of atoms" do
      assert_raise ArgumentError, fn ->
        Metrics.new(:counter, [:http, :request, :count], tags: :my_tag)
      end
    end
  end
end
