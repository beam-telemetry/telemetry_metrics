defmodule Telemetry.MetricsTest do
  use ExUnit.Case

  alias Telemetry.Metrics

  # Tests common to all metric types.
  for metric_type <- [:counter, :sum, :last_value] do
    describe "#{metric_type}/2" do
      test "raises when event name is invalid" do
        assert_raise ArgumentError, fn ->
          event_name = [:my, "event"]
          options = []
          apply(Metrics, unquote(metric_type), [event_name, options])
        end
      end

      test "raises when metric name is invalid" do
        assert_raise ArgumentError, fn ->
          event_name = [:my, :event]
          options = [name: ["metric"]]
          apply(Metrics, unquote(metric_type), [event_name, options])
        end
      end

      test "raises when metadata is invalid" do
        assert_raise ArgumentError, fn ->
          event_name = [:my, :event]
          options = [metadata: 1]
          apply(Metrics, unquote(metric_type), [event_name, options])
        end
      end

      test "raises when tags are invalid" do
        assert_raise ArgumentError, fn ->
          event_name = [:my, :event]
          options = [tags: 1]
          apply(Metrics, unquote(metric_type), [event_name, options])
        end
      end

      test "raises when description is invalid" do
        assert_raise ArgumentError, fn ->
          event_name = [:my, :event]
          options = [description: :"metric description"]
          apply(Metrics, unquote(metric_type), [event_name, options])
        end
      end

      test "raises when unit is invalid" do
        assert_raise ArgumentError, fn ->
          event_name = [:my, :event]
          options = [unit: "second"]
          apply(Metrics, unquote(metric_type), [event_name, options])
        end
      end

      test "returns #{metric_type} specification with default fields" do
        event_name = [:my, :event]
        options = []

        metric = apply(Metrics, unquote(metric_type), [event_name, options])

        assert event_name = metric.event_name
        assert unquote(metric_type) == metric.type
        assert event_name == metric.name
        assert [] == metric.tags
        assert nil == metric.description
        assert :unit == metric.unit
        metadata_fun = metric.metadata
        assert 1 == metadata_fun.(1)
      end

      test "returns #{metric_type} specification with overriden fields" do
        event_name = [:my, :event]
        metric_name = [:metric]
        metadata = ["action"]
        tags = [:controller, "action"]
        description = "a metric"
        unit = :second

        options = [
          name: metric_name,
          metadata: metadata,
          tags: tags,
          description: description,
          unit: unit
        ]

        metric = apply(Metrics, unquote(metric_type), [event_name, options])

        assert event_name == metric.event_name
        assert unquote(metric_type) == metric.type
        assert metric_name == metric.name
        assert tags == metric.tags
        assert description == metric.description
        assert unit == metric.unit
        metadata_fun = metric.metadata

        assert %{"action" => "create"} ==
                 metadata_fun.(%{:controller => UserController, "action" => "create"})
      end
    end
  end

  test "setting :all as metadata returns identity function in metric spec" do
    metric = Metrics.counter([:my, :event], metadata: :all)
    metadata_fun = metric.metadata
    event_metadata = %{controller: UserController, action: "create"}

    assert event_metadata == metadata_fun.(event_metadata)
  end

  test "setting list of terms as metadata returns function returning subset of a map in metric spec" do
    metric = Metrics.counter([:my, :event], metadata: [:action])
    metadata_fun = metric.metadata
    event_metadata = %{controller: UserController, action: "create"}

    assert %{action: "create"} == metadata_fun.(event_metadata)
  end

  test "setting function as metadata returns that function in metric spec" do
    metric = Metrics.counter([:my, :event], metadata: fn _ -> %{constant: "metadata"} end)
    metadata_fun = metric.metadata
    event_metadata = %{controller: UserController, action: "create"}

    assert %{constant: "metadata"} == metadata_fun.(event_metadata)
  end
end
