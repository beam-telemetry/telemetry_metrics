defmodule Telemetry.MetricsTest do
  use ExUnit.Case

  alias Telemetry.Metrics

  # Tests common to all metric types.
  for {metric_type, extra_options} <- [
        counter: [],
        sum: [],
        last_value: [],
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

      test "raises when metadata is invalid" do
        assert_raise ArgumentError, fn ->
          options = [metadata: 1] ++ unquote(extra_options)
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
        metadata_fun = metric.metadata
        assert %{} == metadata_fun.(%{key: 1, another_key: 2})
        measurement_fun = metric.measurement
        assert 3 == measurement_fun.(%{latency: 3, other_value: 2})
      end

      test "returns #{metric_type} specification with overriden fields" do
        name = "my.metric"
        event_name = [:my, :event]
        measurement = :other_value
        metadata = ["action"]
        tags = [:controller, "action"]
        description = "a metric"
        unit = :second

        options =
          [
            event_name: event_name,
            measurement: measurement,
            metadata: metadata,
            tags: tags,
            description: description,
            unit: unit
          ] ++ unquote(extra_options)

        metric = apply(Metrics, unquote(metric_type), [name, options])

        assert event_name == metric.event_name
        assert [:my, :metric] == metric.name
        assert tags == metric.tags
        assert description == metric.description
        assert unit == metric.unit
        metadata_fun = metric.metadata
        measurement_fun = metric.measurement

        assert %{"action" => "create"} ==
                 metadata_fun.(%{:controller => UserController, "action" => "create"})

        assert 2 == measurement_fun.(%{value: 3, other_value: 2})
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

      test "setting :all as metadata returns identity function in metric spec" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "my.event.value",
            [metadata: :all] ++ unquote(extra_options)
          ])

        metadata_fun = metric.metadata
        event_metadata = %{controller: UserController, action: "create"}

        assert event_metadata == metadata_fun.(event_metadata)
      end

      test "setting list of terms as metadata returns function returning subset of a map in metric spec" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "my.event.value",
            [metadata: [:action]] ++ unquote(extra_options)
          ])

        metadata_fun = metric.metadata
        event_metadata = %{controller: UserController, action: "create"}

        assert %{action: "create"} == metadata_fun.(event_metadata)
      end

      test "setting function as metadata returns that function in metric spec" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "my.event.value",
            [metadata: fn _ -> %{constant: "metadata"} end] ++ unquote(extra_options)
          ])

        metadata_fun = metric.metadata
        event_metadata = %{controller: UserController, action: "create"}

        assert %{constant: "metadata"} == metadata_fun.(event_metadata)
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

      test "setting tags and not metadata returns spec with metadata fun filtering only specified tags" do
        tags = [:action]

        metric =
          apply(Metrics, unquote(metric_type), [
            "my.event:value",
            [tags: tags] ++ unquote(extra_options)
          ])

        event_metadata = metric.metadata.(%{controller: UserController, action: :create})
        assert tags == Map.keys(event_metadata)
      end

      test "metadata fun can leave other keys than tags" do
        tags = [:action]
        metadata = [:controller]

        metric =
          apply(Metrics, unquote(metric_type), [
            "my.event:value",
            [tags: tags, metadata: metadata] ++ unquote(extra_options)
          ])

        event_metadata = metric.metadata.(%{controller: UserController, action: :create})
        refute tags == Map.keys(event_metadata)
      end

      test "setting term as measurement returns function returning value under that term in metric spec" do
        metric =
          apply(Metrics, unquote(metric_type), [
            [:my, :event],
            [measurement: :value] ++ unquote(extra_options)
          ])

        measurement_fun = metric.measurement
        event_measurements = %{value: 3, other_value: 2}

        assert 3 == measurement_fun.(event_measurements)
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
        measurement_fun = metric.measurement
        event_measurements = %{value: 3, other_value: 2}
        assert 3 == measurement_fun.(event_measurements)
      end

      test "metric name can be a string" do
        metric =
          apply(Metrics, unquote(metric_type), [
            "my.event.value",
            unquote(extra_options)
          ])

        assert [:my, :event, :value] == metric.name
        assert [:my, :event] == metric.event_name
        measurement_fun = metric.measurement
        event_measurements = %{value: 3, other_value: 2}
        assert 3 == measurement_fun.(event_measurements)
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
    end
  end

  test "distribution/2 raises if bucket boundaries are not increasing" do
    assert_raise ArgumentError, fn ->
      Metrics.distribution("http.request.latency", buckets: [0, 200, 100])
    end
  end

  test "distribution/2 raises if bucket boundaries are empty" do
    assert_raise ArgumentError, fn ->
      Metrics.distribution("http.request.latency", buckets: [])
    end
  end

  test "distribution/2 raises if bucket boundary is not a number" do
    assert_raise ArgumentError, fn ->
      Metrics.distribution("http.request.latency", buckets: [0, 100, "200"])
    end
  end

  test "distribution/2 raises if bucket boundaries are not provided" do
    assert_raise KeyError, fn ->
      Metrics.distribution("http.request.latency", [])
    end
  end
end
