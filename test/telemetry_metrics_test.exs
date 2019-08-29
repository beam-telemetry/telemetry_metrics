defmodule Telemetry.MetricsTest do
  use ExUnit.Case

  alias Telemetry.Metrics

  # Tests common to all metric types.
  for {metric_type, extra_options} <- [
        counter: [],
        sum: [],
        last_value: [],
        summary: [],
        distribution: [buckets: [0, 100, 200]]
      ] do
    describe "#{metric_type}/2" do
      test "raises when metric name is invalid" do
        assert_raise ArgumentError, fn ->
          name = [:my, "event"]
          options = unquote(extra_options)
          apply(Metrics, unquote(metric_type), [name, options])
        end
      end

      test "raises when event name is invalid" do
        assert_raise ArgumentError, fn ->
          options = [event_name: [:my, "event"]] ++ unquote(extra_options)
          apply(Metrics, unquote(metric_type), ["my.metric", options])
        end
      end

      test "raises when tag_values is invalid" do
        assert_raise ArgumentError, fn ->
          options = [tag_values: 1] ++ unquote(extra_options)
          apply(Metrics, unquote(metric_type), ["my.metric", options])
        end
      end

      test "raises when tags are invalid" do
        assert_raise ArgumentError, fn ->
          options = [tags: 1] ++ unquote(extra_options)
          apply(Metrics, unquote(metric_type), ["my.metric", options])
        end
      end

      test "raises when description is invalid" do
        assert_raise ArgumentError, fn ->
          options = [description: :"metric description"] ++ unquote(extra_options)
          apply(Metrics, unquote(metric_type), ["my.metric", options])
        end
      end

      test "raises when unit is invalid" do
        assert_raise ArgumentError, fn ->
          options = [unit: "second"] ++ unquote(extra_options)
          apply(Metrics, unquote(metric_type), ["my.metric", options])
        end
      end

      test "returns #{metric_type} specification with default fields" do
        name = "http.request.latency"
        options = [] ++ unquote(extra_options)

        metric = apply(Metrics, unquote(metric_type), [name, options])

        assert [:http, :request] == metric.event_name
        assert [:http, :request, :latency] == metric.name
        assert [] == metric.tags
        assert nil == metric.description
        assert :unit == metric.unit
        assert :latency = metric.measurement
        tag_values_fun = metric.tag_values
        assert %{key: 1, another_key: 2} == tag_values_fun.(%{key: 1, another_key: 2})
      end

      test "returns #{metric_type} specification with overriden fields" do
        name = "my.metric"
        event_name = [:my, :event]
        measurement = :other_value
        tag_values = &%{:controller => &1.controller, "controller_action" => &1.action}
        tags = [:controller, "controller_action"]
        description = "a metric"
        unit = :second

        options =
          [
            event_name: event_name,
            measurement: measurement,
            tags: tags,
            tag_values: tag_values,
            description: description,
            unit: unit
          ] ++ unquote(extra_options)

        metric = apply(Metrics, unquote(metric_type), [name, options])

        assert event_name == metric.event_name
        assert [:my, :metric] == metric.name
        assert tags == metric.tags
        assert description == metric.description
        assert unit == metric.unit
        assert :other_value = metric.measurement
        tag_values_fun = metric.tag_values

        assert %{:controller => UserController, "controller_action" => "create"} ==
                 tag_values_fun.(%{controller: UserController, action: "create"})
      end

      test "return normalized metric and event name in the specification" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "http.requests.count",
            [event_name: "http.request"] ++ unquote(extra_options)
          ])

        assert [:http, :request] == metric.event_name
        assert [:http, :requests, :count] == metric.name
      end

      test "tag_values default returns identity function in metric spec" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "my.event.value",
            unquote(extra_options)
          ])

        tag_values_fun = metric.tag_values
        event_metadata = %{controller: UserController, action: "create"}

        assert event_metadata == tag_values_fun.(event_metadata)
      end

      test "setting function as tag_values returns that function in metric spec" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "my.event.value",
            [tag_values: fn _ -> %{constant: "metadata"} end] ++ unquote(extra_options)
          ])

        tag_values_fun = metric.tag_values
        event_metadata = %{controller: UserController, action: "create"}

        assert %{constant: "metadata"} == tag_values_fun.(event_metadata)
      end

      test "using metric name with leading, trailing or subsequent dots raises" do
        for name <- [".metric.name", "metric.name.", "metric..name"] do
          assert_raise ArgumentError, fn ->
            apply(Metrics, unquote(metric_type), [
              name,
              unquote(extra_options)
            ])
          end
        end
      end

      test "using event name with leading, trailing or subsequent dots raises" do
        for event_name <- [".event.value", "event.value.", "event..name"] do
          assert_raise ArgumentError, fn ->
            apply(Metrics, unquote(metric_type), [
              "my.metric",
              [event_name: event_name] ++ unquote(extra_options)
            ])
          end
        end
      end

      test "tag_values fun can leave other keys than in metadata" do
        tags = [:action, :some_tag]
        tag_values_fun = fn metadata -> Map.put(metadata, :some_tag, "some_value") end
        event_metadata = %{controller: UserController, action: :create}

        metric =
          apply(Metrics, unquote(metric_type), [
            "my.event:value",
            [tags: tags, tag_values: tag_values_fun] ++ unquote(extra_options)
          ])

        tag_values = metric.tag_values.(event_metadata)
        refute tags == Map.keys(tag_values)
      end

      test "setting term as measurement returns function returning value under that term in metric spec" do
        metric =
          apply(Metrics, unquote(metric_type), [
            [:my, :event],
            [measurement: :value] ++ unquote(extra_options)
          ])

        assert :value == metric.measurement
      end

      test "setting function as measurement returns that function in metric spec" do
        metric =
          apply(Metrics, unquote(metric_type), [
            [:my, :event],
            [measurement: fn _ -> 42 end] ++ unquote(extra_options)
          ])

        measurement_fun = metric.measurement
        event_measurements = %{value: 3, other_value: 2}

        assert 42 == measurement_fun.(event_measurements)
      end

      test "metric name can be a list of atoms" do
        metric =
          apply(Metrics, unquote(metric_type), [
            [:my, :event, :value],
            unquote(extra_options)
          ])

        assert [:my, :event, :value] == metric.name
        assert [:my, :event] == metric.event_name
        assert :value == metric.measurement
      end

      test "metric name can be a string" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "my.event.value",
            unquote(extra_options)
          ])

        assert [:my, :event, :value] == metric.name
        assert [:my, :event] == metric.event_name
        assert :value = metric.measurement
      end

      test "raises when metric name is empty" do
        for name <- [[], ""] do
          assert_raise ArgumentError, fn ->
            apply(Metrics, unquote(metric_type), [
              name,
              unquote(extra_options)
            ])
          end
        end
      end

      test "raises when event name derived from metric name is empty" do
        assert_raise ArgumentError, fn ->
          apply(Metrics, unquote(metric_type), [
            "latency",
            unquote(extra_options)
          ])
        end
      end

      test "raises when event name is empty" do
        for event_name <- [[], ""] do
          assert_raise ArgumentError, fn ->
            apply(Metrics, unquote(metric_type), [
              "http.request.latency",
              [event_name: event_name] ++ unquote(extra_options)
            ])
          end
        end
      end

      test "raises when first element of unit-conversion tuple is not a valid time unit" do
        assert_raise ArgumentError, fn ->
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:byte, :millisecond}] ++ unquote(extra_options)
          ])
        end
      end

      test "raises when second element of unit-conversion tuple is not a valid time unit" do
        assert_raise ArgumentError, fn ->
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:millisecond, :byte}] ++ unquote(extra_options)
          ])
        end
      end

      test "raises when unit-conversion tuple is not a two-element tuple" do
        assert_raise ArgumentError, fn ->
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:native, :millisecond, :nanosecond}] ++ unquote(extra_options)
          ])
        end
      end

      test "sets the unit in the definition to the second element of the unit-conversion tuple" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:native, :millisecond}] ++ unquote(extra_options)
          ])

        assert metric.unit == :millisecond
      end

      test "raises when unit-conversion tuple is provided but measurement is not a number" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:native, :millisecond}] ++ unquote(extra_options)
          ])

        assert_raise ArithmeticError, fn ->
          metric.measurement.(%{latency: :not_a_number})
        end
      end

      test "raises when unit-conversion tuple is provided but measurement function doesn't return a number" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:native, :millisecond}, measurement: fn _ -> :not_a_number end] ++
              unquote(extra_options)
          ])

        assert_raise ArithmeticError, fn ->
          metric.measurement.(%{latency: 250})
        end
      end

      test "doesn't raise when measurement is not a number but no unit-conversion is required" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: :millisecond, measurement: fn _ -> :not_a_number end] ++ unquote(extra_options)
          ])

        assert metric.measurement.(%{latency: 250}) == :not_a_number
      end

      test "doesn't convert a unit if both units are the same" do
        for unit <- [
              :native,
              :second,
              :millisecond,
              :microsecond,
              :nanosecond,
              :byte,
              :kilobyte,
              :megabyte
            ] do
          metric =
            apply(Metrics, unquote(metric_type), [
              "http.request.latency",
              [unit: {unit, unit}] ++ unquote(extra_options)
            ])

          refute is_function(metric.measurement)
        end
      end

      test "converts a measurement under key from one regular time unit to another" do
        units = [:native, :second, :millisecond, :microsecond, :nanosecond]
        measurement = :rand.uniform(10_000_000)

        # We need to filter out cases where conversion doesn't change anything, because then the
        # measurement inside metric definition is not a function but a key, and the test fails.
        # We also can't simply filter using `from != to`, because native is approximately equal to
        # one of the regular time units, and the conversion ratio would still be equal to 1.
        for from <- units, to <- units, measurement != converted_unit(measurement, from, to) do
          metric =
            apply(Metrics, unquote(metric_type), [
              "http.request.latency",
              [unit: {from, to}] ++ unquote(extra_options)
            ])

          measurements = %{latency: measurement}

          assert metric.measurement.(measurements) == converted_unit(measurement, from, to)
        end
      end

      test "converts a measurement under key from byte to kilobyte" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:byte, :kilobyte}] ++ unquote(extra_options)
          ])

        measurement = 76_000_000

        measurements = %{latency: measurement}

        assert metric.measurement.(measurements) == 76_000
      end

      test "converts a measurement under key from byte to megabyte" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:byte, :megabyte}] ++ unquote(extra_options)
          ])

        measurement = 76_000_000

        measurements = %{latency: measurement}

        assert metric.measurement.(measurements) == 76
      end

      test "converts a measurement under key from kilobyte to byte" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:kilobyte, :byte}] ++ unquote(extra_options)
          ])

        measurement = 76_000

        measurements = %{latency: measurement}

        assert metric.measurement.(measurements) == 76_000_000
      end

      test "converts a measurement under key from kilobyte to megabyte" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:kilobyte, :megabyte}] ++ unquote(extra_options)
          ])

        measurement = 76_000

        measurements = %{latency: measurement}

        assert metric.measurement.(measurements) == 76
      end

      test "converts a measurement under key from megabyte to byte" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:megabyte, :byte}] ++ unquote(extra_options)
          ])

        measurement = 76

        measurements = %{latency: measurement}

        assert metric.measurement.(measurements) == 76_000_000
      end

      test "converts a measurement under key from megabyte to kilobyte" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:megabyte, :kilobyte}] ++ unquote(extra_options)
          ])

        measurement = 76

        measurements = %{latency: measurement}

        assert metric.measurement.(measurements) == 76_000
      end

      test "converts a result of measurement function from one regular time unit to another" do
        units = [:native, :second, :millisecond, :microsecond, :nanosecond]
        measurement = :rand.uniform(10_000_000)

        for from <- units, to <- units, from != to do
          metric =
            apply(Metrics, unquote(metric_type), [
              "http.request.latency",
              [unit: {from, to}, measurement: fn _ -> measurement end] ++ unquote(extra_options)
            ])

          assert metric.measurement.(%{}) == converted_unit(measurement, from, to)
        end
      end

      test "converts a result of measurement function from byte to kilobyte" do
        measurement = fn _ -> 76_000_000 end

        metric =
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:byte, :kilobyte}, measurement: measurement] ++ unquote(extra_options)
          ])

        assert metric.measurement.(%{}) == 76_000
      end

      test "converts a result of measurement function from byte to megabyte" do
        measurement = fn _ -> 76_000_000 end

        metric =
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:byte, :megabyte}, measurement: measurement] ++ unquote(extra_options)
          ])

        assert metric.measurement.(%{}) == 76
      end

      test "converts a result of measurement function from kilobyte to byte" do
        measurement = fn _ -> 76_000 end

        metric =
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:kilobyte, :byte}, measurement: measurement] ++ unquote(extra_options)
          ])

        assert metric.measurement.(%{}) == 76_000_000
      end

      test "converts a result of measurement function from kilobyte to megabyte" do
        measurement = fn _ -> 76_000 end

        metric =
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:kilobyte, :megabyte}, measurement: measurement] ++ unquote(extra_options)
          ])

        assert metric.measurement.(%{}) == 76
      end

      test "converts a result of measurement function from megabyte to byte" do
        measurement = fn _ -> 76 end

        metric =
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:megabyte, :byte}, measurement: measurement] ++ unquote(extra_options)
          ])

        assert metric.measurement.(%{}) == 76_000_000
      end

      test "converts a result of measurement function from megabyte to kilobyte" do
        measurement = fn _ -> 76 end

        metric =
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:megabyte, :kilobyte}, measurement: measurement] ++ unquote(extra_options)
          ])

        assert metric.measurement.(%{}) == 76_000
      end
    end
  end

  test "distribution/2 allows {range, step} buckets" do
    assert Metrics.distribution("http.request.latency", buckets: {100..300, 100}).buckets ==
             [100, 200, 300]

    assert_raise ArgumentError, fn ->
      Metrics.distribution("http.request.latency", buckets: {300..100, 100})
    end

    assert_raise ArgumentError, fn ->
      Metrics.distribution("http.request.latency", buckets: {100..350, 100})
    end
  end

  test "distribution/2 allows list buckets" do
    assert_raise ArgumentError, fn ->
      Metrics.distribution("http.request.latency", buckets: [0, 200, 100])
    end

    assert_raise ArgumentError, fn ->
      Metrics.distribution("http.request.latency", buckets: [])
    end

    assert_raise ArgumentError, fn ->
      Metrics.distribution("http.request.latency", buckets: [0, 100, "200"])
    end
  end

  test "distribution/2 raises if bucket boundaries are not provided" do
    assert_raise KeyError, fn ->
      Metrics.distribution("http.request.latency", [])
    end
  end

  defp converted_unit(measurement, from_unit, to_unit) do
    measurement * conversion_ratio(from_unit, to_unit)
  end

  defp conversion_ratio(unit, unit), do: 1

  defp conversion_ratio(from, to) when from == :native or to == :native do
    case System.convert_time_unit(1, from, to) do
      0 ->
        1 / System.convert_time_unit(1, to, from)

      ratio ->
        ratio
    end
  end

  # Make the conversion for regular units more explicit in tests, so that we're sure we get the
  # correct results.
  defp conversion_ratio(:second, :millisecond), do: 1_000
  defp conversion_ratio(:second, :microsecond), do: 1_000_000
  defp conversion_ratio(:second, :nanosecond), do: 1_000_000_000
  defp conversion_ratio(:millisecond, :microsecond), do: 1_000
  defp conversion_ratio(:millisecond, :nanosecond), do: 1_000_000
  defp conversion_ratio(:microsecond, :nanosecond), do: 1_000
  defp conversion_ratio(from, to), do: 1 / conversion_ratio(to, from)
end
