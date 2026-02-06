defmodule Telemetry.MetricsTest do
  use ExUnit.Case

  alias Telemetry.Metrics

  # Tests common to all metric types.
  for metric_type <- [:counter, :sum, :last_value, :summary, :distribution] do
    describe "#{metric_type}/2" do
      test "raises when metric name is invalid" do
        assert_raise ArgumentError, fn ->
          name = [:my, "event"]
          apply(Metrics, unquote(metric_type), [name])
        end
      end

      test "raises when event name is invalid" do
        assert_raise ArgumentError, fn ->
          options = [event_name: [:my, "event"]]
          apply(Metrics, unquote(metric_type), ["my.metric", options])
        end
      end

      test "raises when tag_values is invalid" do
        assert_raise ArgumentError, fn ->
          options = [tag_values: 1]
          apply(Metrics, unquote(metric_type), ["my.metric", options])
        end
      end

      test "raises when tags are invalid" do
        assert_raise ArgumentError, fn ->
          options = [tags: 1]
          apply(Metrics, unquote(metric_type), ["my.metric", options])
        end
      end

      test "raises when description is invalid" do
        assert_raise ArgumentError, fn ->
          options = [description: :"metric description"]
          apply(Metrics, unquote(metric_type), ["my.metric", options])
        end
      end

      test "raises when unit is invalid" do
        assert_raise ArgumentError, fn ->
          options = [unit: "second"]
          apply(Metrics, unquote(metric_type), ["my.metric", options])
        end
      end

      test "raises when reporter options is invalid" do
        assert_raise ArgumentError, fn ->
          options = [reporter_options: [:avg]]
          apply(Metrics, unquote(metric_type), ["my.metric", options])
        end
      end

      test "returns #{metric_type} specification with default fields" do
        name = "http.request.latency"

        metric = apply(Metrics, unquote(metric_type), [name])

        assert [:http, :request] == metric.event_name
        assert [:http, :request, :latency] == metric.name
        assert [] == metric.tags
        assert nil == metric.description
        assert :unit == metric.unit
        assert :latency = metric.measurement
        assert [] = metric.reporter_options
        tag_values_fun = metric.tag_values
        assert %{key: 1, another_key: 2} == tag_values_fun.(%{key: 1, another_key: 2})
      end

      test "returns #{metric_type} specification with overridden fields" do
        name = "my.metric"
        event_name = [:my, :event]
        measurement = :other_value
        tag_values = &%{:controller => &1.controller, "controller_action" => &1.action}
        tags = [:controller, "controller_action"]
        description = "a metric"
        unit = :second
        reporter_options = [sample_rate: 0.1]

        options = [
          event_name: event_name,
          measurement: measurement,
          tags: tags,
          tag_values: tag_values,
          description: description,
          unit: unit,
          reporter_options: reporter_options
        ]

        metric = apply(Metrics, unquote(metric_type), [name, options])

        assert event_name == metric.event_name
        assert [:my, :metric] == metric.name
        assert tags == metric.tags
        assert description == metric.description
        assert unit == metric.unit
        assert :other_value = metric.measurement
        assert reporter_options == metric.reporter_options
        tag_values_fun = metric.tag_values

        assert %{:controller => UserController, "controller_action" => "create"} ==
                 tag_values_fun.(%{controller: UserController, action: "create"})
      end

      test "return normalized metric and event name in the specification" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "http.requests.count",
            [event_name: "http.request"]
          ])

        assert [:http, :request] == metric.event_name
        assert [:http, :requests, :count] == metric.name
      end

      test "tag_values default returns identity function in metric spec" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "my.event.value"
          ])

        tag_values_fun = metric.tag_values
        event_metadata = %{controller: UserController, action: "create"}

        assert event_metadata == tag_values_fun.(event_metadata)
      end

      test "setting function as tag_values returns that function in metric spec" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "my.event.value",
            [tag_values: fn _ -> %{constant: "metadata"} end]
          ])

        tag_values_fun = metric.tag_values
        event_metadata = %{controller: UserController, action: "create"}

        assert %{constant: "metadata"} == tag_values_fun.(event_metadata)
      end

      test "setting function as filter returns that function in metric spec" do
        keep_metric =
          apply(Metrics, unquote(metric_type), [
            "my.repo.query",
            [keep: &match?(%{repo: :my_app_read_only_repo}, &1)]
          ])

        drop_metric =
          apply(Metrics, unquote(metric_type), [
            "my.repo.query",
            [drop: &match?(%{repo: :my_app_read_only_repo}, &1)]
          ])

        assert keep_metric.keep.(%{repo: :my_app_read_only_repo})
        refute keep_metric.keep.(%{repo: :my_app_repo})

        refute drop_metric.keep.(%{repo: :my_app_read_only_repo})
        assert drop_metric.keep.(%{repo: :my_app_repo})
      end

      test "using event filter that evaluates both metadata and measurement" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "my.repo.query",
            [keep: &(match?(%{repo: :my_app_read_only_repo}, &1) and &2.duration > 100)]
          ])

        assert metric.keep.(%{repo: :my_app_read_only_repo}, %{duration: 200})
        refute metric.keep.(%{repo: :my_app_read_only_repo}, %{duration: 50})
      end

      test "setting both keep and drop options raises" do
        assert_raise ArgumentError, fn ->
          apply(Metrics, unquote(metric_type), [
            "my.event.value",
            [
              keep: &match?(%{some: :value}, &1),
              drop: &match?(%{some: :other_value}, &1)
            ]
          ])
        end
      end

      test "using metric name with leading, trailing or subsequent dots raises" do
        for name <- [".metric.name", "metric.name.", "metric..name"] do
          assert_raise ArgumentError, fn ->
            apply(Metrics, unquote(metric_type), [
              name
            ])
          end
        end
      end

      test "using event name with leading, trailing or subsequent dots raises" do
        for event_name <- [".event.value", "event.value.", "event..name"] do
          assert_raise ArgumentError, fn ->
            apply(Metrics, unquote(metric_type), [
              "my.metric",
              [event_name: event_name]
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
            [tags: tags, tag_values: tag_values_fun]
          ])

        tag_values = metric.tag_values.(event_metadata)
        refute tags == Map.keys(tag_values)
      end

      test "setting term as measurement returns function returning value under that term in metric spec" do
        metric =
          apply(Metrics, unquote(metric_type), [
            [:my, :event],
            [measurement: :value]
          ])

        assert :value == metric.measurement
      end

      test "setting unary function as measurement returns that function in metric spec" do
        metric =
          apply(Metrics, unquote(metric_type), [
            [:my, :event],
            [measurement: fn _ -> 42 end]
          ])

        measurement_fun = metric.measurement
        event_measurements = %{value: 3, other_value: 2}

        assert 42 == measurement_fun.(event_measurements)
      end

      test "setting binary function as measurement returns that function in metric spec" do
        metric =
          apply(Metrics, unquote(metric_type), [
            [:my, :event],
            [measurement: fn _measurement, metadata -> length(metadata.messages) end]
          ])

        measurement_fun = metric.measurement
        event_measurements = %{value: 3, other_value: 2}

        assert 42 ==
                 measurement_fun.(event_measurements, %{messages: List.duplicate("message", 42)})
      end

      test "metric name can be a list of atoms" do
        metric =
          apply(Metrics, unquote(metric_type), [
            [:my, :event, :value]
          ])

        assert [:my, :event, :value] == metric.name
        assert [:my, :event] == metric.event_name
        assert :value == metric.measurement
      end

      test "metric name can be a string" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "my.event.value"
          ])

        assert [:my, :event, :value] == metric.name
        assert [:my, :event] == metric.event_name
        assert :value = metric.measurement
      end

      test "raises when metric name is empty" do
        for name <- [[], ""] do
          assert_raise ArgumentError, fn ->
            apply(Metrics, unquote(metric_type), [
              name
            ])
          end
        end
      end

      test "raises when metric name is not a string or list of atoms" do
        for name <- [nil, [nil]] do
          assert_raise ArgumentError, fn ->
            apply(Metrics, unquote(metric_type), [name])
          end
        end
      end

      test "raises when event name derived from metric name is empty" do
        assert_raise ArgumentError,
                     "event_name can't be empty (metric must be namespaced or :event_name explicitly set)",
                     fn ->
                       apply(Metrics, unquote(metric_type), [
                         "latency"
                       ])
                     end
      end

      test "raises when event name is empty" do
        for event_name <- [[], ""] do
          assert_raise ArgumentError, fn ->
            apply(Metrics, unquote(metric_type), [
              "http.request.latency",
              [event_name: event_name]
            ])
          end
        end
      end

      test "raises when event filter is not a function with an arity of 1 or 2" do
        Enum.each([keep: fn -> true end, drop: fn -> true end], fn filter ->
          assert_raise ArgumentError, fn ->
            apply(Metrics, unquote(metric_type), [
              "ecto.query.queue_time",
              [filter]
            ])
          end
        end)
      end

      test "raises when first element of unit-conversion tuple is not a valid time unit" do
        assert_raise ArgumentError, fn ->
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:byte, :millisecond}]
          ])
        end
      end

      test "raises when second element of unit-conversion tuple is not a valid time unit" do
        assert_raise ArgumentError, fn ->
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:millisecond, :byte}]
          ])
        end
      end

      test "raises when unit-conversion tuple is not a two-element tuple" do
        assert_raise ArgumentError, fn ->
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:native, :millisecond, :nanosecond}]
          ])
        end
      end

      test "sets the unit in the definition to the second element of the unit-conversion tuple" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:native, :millisecond}]
          ])

        assert metric.unit == :millisecond
      end

      test "does not raise when unit-conversion tuple is provided but measurement is nil" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:native, :millisecond}]
          ])

        assert metric.measurement.(%{latency: nil}) == nil
      end

      test "does not raise when unit-conversion tuple is provided but measurement is missing" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "http.request.missing_measurement",
            [unit: {:native, :millisecond}]
          ])

        assert metric.measurement.(%{}) == nil
      end

      test "raises when unit-conversion tuple is provided but measurement is not a number" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:native, :millisecond}]
          ])

        assert_raise ArithmeticError, fn ->
          metric.measurement.(%{latency: :not_a_number})
        end
      end

      test "raises when unit-conversion tuple is provided but measurement function doesn't return a number" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: {:native, :millisecond}, measurement: fn _ -> :not_a_number end]
          ])

        assert_raise ArithmeticError, fn ->
          metric.measurement.(%{latency: 250})
        end
      end

      test "doesn't raise when measurement is not a number but no unit-conversion is required" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "http.request.latency",
            [unit: :millisecond, measurement: fn _ -> :not_a_number end]
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
              [unit: {unit, unit}]
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
              [unit: {from, to}]
            ])

          measurements = %{latency: measurement}

          assert metric.measurement.(measurements) == converted_unit(measurement, from, to)
        end
      end

      test "converts a measurement under key from one byte unit to another" do
        units = [
          {{:byte, 76_000_000}, {:kilobyte, 76_000}},
          {{:byte, 76_000_000}, {:megabyte, 76}},
          {{:kilobyte, 76_000}, {:byte, 76_000_000}},
          {{:kilobyte, 76_000}, {:megabyte, 76}},
          {{:megabyte, 76}, {:byte, 76_000_000}},
          {{:megabyte, 76}, {:kilobyte, 76_000}}
        ]

        for {{from, original}, {to, converted}} <- units do
          metric =
            apply(Metrics, unquote(metric_type), [
              "http.request.latency",
              [unit: {from, to}]
            ])

          measurements = %{latency: original}

          assert metric.measurement.(measurements) == converted
        end
      end

      test "converts a result of measurement function from one regular time unit to another" do
        units = [:native, :second, :millisecond, :microsecond, :nanosecond]
        measurement = :rand.uniform(10_000_000)

        for from <- units, to <- units, from != to do
          metric =
            apply(Metrics, unquote(metric_type), [
              "http.request.latency",
              [unit: {from, to}, measurement: fn _ -> measurement end]
            ])

          assert metric.measurement.(%{}) == converted_unit(measurement, from, to)
        end
      end

      test "converts a result of binary measurement function from one regular time unit to another" do
        units = [:native, :second, :millisecond, :microsecond, :nanosecond]
        measurement = :rand.uniform(10_000_000)

        for from <- units, to <- units, from != to do
          metric =
            apply(Metrics, unquote(metric_type), [
              "http.request.latency",
              [unit: {from, to}, measurement: fn _measurements, _metadata -> measurement end]
            ])

          assert metric.measurement.(%{}, %{}) == converted_unit(measurement, from, to)
        end
      end

      test "converts a result of measurement function from one regular byte unit to another" do
        units = [
          {{:byte, 76_000_000}, {:kilobyte, 76_000}},
          {{:byte, 76_000_000}, {:megabyte, 76}},
          {{:kilobyte, 76_000}, {:byte, 76_000_000}},
          {{:kilobyte, 76_000}, {:megabyte, 76}},
          {{:megabyte, 76}, {:byte, 76_000_000}},
          {{:megabyte, 76}, {:kilobyte, 76_000}}
        ]

        for {{from, original}, {to, converted}} <- units do
          measurement = fn _ -> original end

          metric =
            apply(Metrics, unquote(metric_type), [
              "http.request.latency",
              [unit: {from, to}, measurement: measurement]
            ])

          assert metric.measurement.(%{}) == converted
        end
      end
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
