defmodule Telemetry.MetricsTest do
  use ExUnit.Case

  # Tests common to all metric types.
  for metric_type <- [:counter, :sum, :last_value] do
    describe "#{metric_type}/2" do
      test "raises when event name is invalid" do
        assert_raise ArgumentError, fn ->
          event_name = [:my, "event"]
          options = []
          apply(Telemetry.Metrics, unquote(metric_type), [event_name, options])
        end
      end

      test "raises when metric name is invalid" do
        assert_raise ArgumentError, fn ->
          event_name = [:my, :event]
          options = [name: ["metric"]]
          apply(Telemetry.Metrics, unquote(metric_type), [event_name, options])
        end
      end

      test "raises when tags fun is invalid" do
        assert_raise ArgumentError, fn ->
          event_name = [:my, :event]
          options = [tags_fun: fn x, y -> %{x: x, y: y} end]
          apply(Telemetry.Metrics, unquote(metric_type), [event_name, options])
        end
      end

      test "raises when tag keys are invalid" do
        assert_raise ArgumentError, fn ->
          event_name = [:my, :event]
          options = [tag_keys: ["tag"]]
          apply(Telemetry.Metrics, unquote(metric_type), [event_name, options])
        end
      end

      test "raises when description is invalid" do
        assert_raise ArgumentError, fn ->
          event_name = [:my, :event]
          options = [description: :"metric description"]
          apply(Telemetry.Metrics, unquote(metric_type), [event_name, options])
        end
      end

      test "raises when unit is invalid" do
        assert_raise ArgumentError, fn ->
          event_name = [:my, :event]
          options = [unit: "second"]
          apply(Telemetry.Metrics, unquote(metric_type), [event_name, options])
        end
      end

      test "returns #{metric_type} specification with default fields" do
        event_name = [:my, :event]
        options = []

        metric = apply(Telemetry.Metrics, unquote(metric_type), [event_name, options])

        assert event_name = metric.event_name
        assert unquote(metric_type) == metric.type
        assert event_name == metric.name
        assert nil == metric.tags_fun
        assert [] == metric.tag_keys
        assert "" == metric.description
        assert :unit == metric.unit
      end

      test "returns #{metric_type} specification with overriden fields" do
        event_name = [:my, :event]
        metric_name = [:metric]
        tags_fun = fn metadata -> metadata end
        tag_keys = [:tag1, :tag2]
        description = "a metric"
        unit = :second

        options = [
          name: metric_name,
          tags_fun: tags_fun,
          tag_keys: tag_keys,
          description: description,
          unit: unit
        ]

        metric = apply(Telemetry.Metrics, unquote(metric_type), [event_name, options])

        assert event_name == metric.event_name
        assert unquote(metric_type) == metric.type
        assert metric_name == metric.name
        assert tags_fun == metric.tags_fun
        assert tag_keys == metric.tag_keys
        assert description == metric.description
        assert unit == metric.unit
      end
    end
  end
end
