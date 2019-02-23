defmodule Telemetry.Metrics do
  @moduledoc """
  Data model and specifications for aggregating Telemetry events.

  Metrics are responsible for aggregating Telemetry events with the same name in order to gain any
  useful knowledge about the events.

  Please note that Telemetry.Metrics package itself doesn't provide any functionality for
  aggregating metrics. This library only defines the data model and specifications for aggregations
  which should be implemented by reporters - libraries exporting metrics to external systems. You
  can read more about reporters in the "Reporters" section below.

  ## Data model

  `Telemetry.Metrics` imposes a multi-dimensional data model - a single metric may generate multiple
  aggregations, each aggregation being bound to a unique set of tag values. Tags are pairs of
  key-values derived from event metadata (in the simplest case, tags are a subset of the metadata).
  Based on the tag values, the value of the event will be used to generate one of the aggregations.

  For example, imagine that you want to count how many requests are being made against your web
  application. On each request, you might emit an event with the name of the controller and action
  handling that request, e.g.:

      :telemetry.execute([:http, :request], %{latency: 227}, %{controller: "user_controller", action: "index"})
      :telemetry.execute([:http, :request], %{latency: 128}, %{controller: "user_controller", action: "index"})
      :telemetry.execute([:http, :request], %{latency: 271}, %{controller: "user_controller", action: "create"})
      :telemetry.execute([:http, :request], %{latency: 121}, %{controller: "product_controller", action: "get"})

  With multi-dimensional data model, the result of aggregating those events by `:controller` and
  `:action` tags would look like this:

  | controller           | action   | count |
  |----------------------|----------|-------|
  | `user_controller`    | `index`  | 2     |
  | `user_controller`    | `create` | 1     |
  | `product_controller` | `get`    | 1     |

  You can see that the request count is broken down by unique set of tag values.

  ## Metric types

  Metric type specifies how the event values are aggregated. `Telemetry.Metrics` aims to define
  a set of metric types covering the most common instrumentation patterns.

  Metric types below are heavily inspired by [OpenCensus](https://opencensus.io).

  ### Counter

  Value of the counter metric is the number of emitted events, regardless of event value. It's
  monotonically increasing and its value is never reset.

  ### Sum

  Value of the sum metric is the sum of event values.

  ### LastValue

  Value of this metric is the value of the most recent event.

  ### Distribution

  The value of this metric is a histogram distribution of event values, i.e. how many events were
  emitted with values falling into defined buckets. Histogram values can be used to compute
  approximation of useful statistics about the data, like quantiles, minimum or maximum.

  For example, given boundaries `[0, 100, 200]`, the distribution metric produces four values:
  * number of event values less than or equal to 0
  * number of event values greater than 0 and less than or equal to 100
  * number of event values greater than 100 and less than or equal to 200
  * number of event values greater than 200

  ## Metric specifications

  Metric specification is a data structure describing the metric - its name, type, name of the
  events aggregated by the metric, etc. The structure of metric specification is relevant only to
  authors of reporters.

  Metric specifications are created using one of the four functions: `counter/2`, `sum/2`,
  `last_value/2` and `distribution/2`. Each of those functions returns a specification of metric
  of the corresponding type.

  The first argument to all these functions is the metric name. Metric name can be provided as
  a string (e.g. `"http.request.latency"`) or a list of atoms (`[:http, :request, :latency]`). If not
  overriden in the metric options, metric name also determines the name of Telemetry event and
  measurement used to produce metric values. In the `"http.request.latency"` example, the source
  event name is `[:http, :request]` and metric values are drawn from `:latency` measurement.

  > Note: do not use data from external sources as metric or event names! Since they are converted
  > to atoms, your application becomes vulnerable to atom leakage and might run out of memory.

  The second argument is a list of options. Below is the description of the options common to all
  metric types:

    * `:event_name` - the source event name. Can be represented either as a string (e.g.
      `"http.request"`) or a list of atoms (`[:http, :request]`). By default the event name is all but
      the last segment of the metric name.
    * `:measurement` - the event measurement used as a source of a metric values. By default it is
      the last segment of the metric name. It can be either an arbitrary term, a key in the event's
      measurements map, or a function accepting the whole measurements map and returning the actual
      value to be used.
      * `:tags` - a subset of metadata keys by which aggregations will be broken down. If `:tags`
      are set but `:metadata` isn't, then `:metadata` is set to the same value as `:tags` for
      convenience. Defaults to an empty list.
    * `:tag_values` - a function that receives the metadata and returns a map with the tags as keys
      and their respective values. Defaults to returning the metadata itself.
    * `:description` - human-readable description of the metric. Might be used by reporters for
      documentation purposes. Defaults to `nil`.
    * `:unit` - an atom describing the unit of event values. Might be used by reporters for
      documentation purposes. Defaults to `:unit`.

  ## Reporters

  Reporters take metric definitions as an input, subscribe to relevant events and update the metrics
  when the events are emitted. Updating the metric might involve publishing the metrics periodically,
  or on demand, to external systems. `Telemetry.Metrics` defines only specification for metric types,
  and reporters should provide actual implementation for these aggregations.

  ### Rationale

  The design proposed by `Telemetry.Metrics` might look controversial - unlike most of the libraries
  available on the BEAM, it doesn't aggregate metrics itself, it merely defines what users should
  expect when using the reporters.

  If `Telemetry.Metrics` would aggregate metrics, the way those aggregations work would be imposed
  on the system where the metrics are published to. For example, counters in StatsD are reset on
  every flush and can be decremented, whereas counters in Prometheus are monotonically increasing.
  `Telemetry.Metrics` doesn't focus on those details - instead, it describes what the end user,
  operator, expects to see when using the metric of particular type. This implies that in most
  cases aggregated metrics won't be visible inside the BEAM, but in exchange aggregations can be
  implemented in a way that makes most sense for particular system.

  Finally, one could also implement an in-VM "reporter" which would aggregate the metrics and expose
  them inside the BEAM. When there is a need to swap the reporters, and if both reporters are
  following the metric types specification, then the end result of aggregation is the same,
  regardless of the backend system in use.

  ### Requirements for reporters

  Reporters should accept metric specifications and subscribe to relevant events. When those events
  are emitted, metric should be updated (either in-memory or by contacting external system) in such
  a way that the user is able to view metric values as described in the "Metric types" section.

  If the reporter does not support the metric given to it, it should log a warning.

  If the map returned by `tag_values` does not contain a key specified in the `:tags` option,
  it should log a warning.

  Reporters should also document how `Telemetry.Metrics` metric types, names, and tags are translated to
  metric types and identifiers in the system they publish metrics to.

  We recommend reporters to subscribe to those events in a process that also removes the installed
  subscriptions on shutdown. This can be done by trapping exists and implementing the terminate
  callback. It is very important that the code executed on every event does not fail, as that would
  cause the handler to be permanently removed.
  """

  require Logger

  alias Telemetry.Metrics.{Counter, Sum, LastValue, Distribution}

  @typedoc """
  The name of the metric, either as string or a list of atoms.
  """
  @type metric_name :: String.t() | normalized_metric_name()

  @typedoc """
  The name of the metric represented as a list of atoms.
  """
  @type normalized_metric_name :: [atom(), ...]

  @type measurement :: term() | (:telemetry.event_measurements() -> number())
  @type tag :: term()
  @type tags :: [tag()]
  @type tag_values :: (:telemetry.event_metadata() -> :telemetry.event_metadata())
  @type description :: nil | String.t()
  @type unit :: atom()
  @type counter_options :: [metric_option()]
  @type sum_options :: [metric_option()]
  @type last_value_options :: [metric_option()]
  @type distribution_options :: [metric_option() | {:buckets, Distribution.buckets()}]
  @type metric_option ::
          {:event_name, :telemetry.event_name()}
          | {:measurement, measurement()}
          | {:tags, tags()}
          | {:tag_values, tag_values()}
          | {:description, description()}
          | {:unit, unit()}

  @typedoc """
  Common fields for metric specifications

  Reporters should assume that these fields are present in all metric specifications.
  """
  @type t :: %{
          __struct__: module(),
          name: normalized_metric_name(),
          measurement: measurement(),
          event_name: :telemetry.event_name(),
          tags: tags(),
          tag_values: (:telemetry.event_metadata() -> :telemetry.event_metadata()),
          description: description(),
          unit: unit()
        }

  # API

  @doc """
  Returns a specification of counter metric.

  See "Metric specifications" section in the top-level documentation of this module for more
  information.

  ## Example

      counter(
        "http.request.count",
        tags: [:controller, :action]
      )
  """
  @spec counter(metric_name(), counter_options()) :: Counter.t()
  def counter(metric_name, options \\ []) do
    metric_name = validate_metric_or_event_name!(metric_name)
    {event_name, [measurement]} = Enum.split(metric_name, -1)
    {event_name, options} = Keyword.pop(options, :event_name, event_name)
    {measurement, options} = Keyword.pop(options, :measurement, measurement)
    event_name = validate_metric_or_event_name!(event_name)
    validate_metric_options!(options)
    options = fill_in_default_metric_options(options)

    %Counter{
      name: metric_name,
      event_name: event_name,
      measurement: measurement,
      tags: Keyword.fetch!(options, :tags),
      tag_values: options |> Keyword.fetch!(:tag_values) |> tag_values_spec_to_function(),
      description: Keyword.fetch!(options, :description),
      unit: Keyword.fetch!(options, :unit)
    }
  end

  @doc """
  Returns a specification of sum metric.

  See "Metric specifications" section in the top-level documentation of this module for more
  information.

  ## Example

      sum(
        "user.session_count",
        event_name: "user.session_count",
        measurement: :delta,
        tags: [:role]
      )
  """
  @spec sum(metric_name(), sum_options()) :: Sum.t()
  def sum(metric_name, options \\ []) do
    metric_name = validate_metric_or_event_name!(metric_name)
    {event_name, [measurement]} = Enum.split(metric_name, -1)
    {event_name, options} = Keyword.pop(options, :event_name, event_name)
    {measurement, options} = Keyword.pop(options, :measurement, measurement)
    event_name = validate_metric_or_event_name!(event_name)
    validate_metric_options!(options)
    options = fill_in_default_metric_options(options)

    %Sum{
      name: metric_name,
      event_name: event_name,
      measurement: measurement,
      tags: Keyword.fetch!(options, :tags),
      tag_values: options |> Keyword.fetch!(:tag_values) |> tag_values_spec_to_function(),
      description: Keyword.fetch!(options, :description),
      unit: Keyword.fetch!(options, :unit)
    }
  end

  @doc """
  Returns a specification of last value metric.

  See "Metric specifications" section in the top-level documentation of this module for more
  information.

  ## Example

      last_value(
        "vm.memory.total",
        description: "Total amount of memory allocated by the Erlang VM", unit: :byte
      )
  """
  @spec last_value(metric_name(), last_value_options()) :: LastValue.t()
  def last_value(metric_name, options \\ []) do
    metric_name = validate_metric_or_event_name!(metric_name)
    {event_name, [measurement]} = Enum.split(metric_name, -1)
    {event_name, options} = Keyword.pop(options, :event_name, event_name)
    {measurement, options} = Keyword.pop(options, :measurement, measurement)
    event_name = validate_metric_or_event_name!(event_name)
    validate_metric_options!(options)
    options = fill_in_default_metric_options(options)

    %LastValue{
      name: metric_name,
      event_name: event_name,
      measurement: measurement,
      tags: Keyword.fetch!(options, :tags),
      tag_values: options |> Keyword.fetch!(:tag_values) |> tag_values_spec_to_function(),
      description: Keyword.fetch!(options, :description),
      unit: Keyword.fetch!(options, :unit)
    }
  end

  @doc """
  Returns a specification of distribution metric.

  For a distribution metric, it is required that you include a `:buckets` field in the options
  keyword list.

  See "Metric specifications" section in the top-level documentation of this module for more
  information.

  ## Example

      distribution(
        "http.request.latency",
        buckets: [100, 200, 300],
        tags: [:controller, :action],
      )
  """
  @spec distribution(metric_name(), distribution_options()) :: Distribution.t()
  def distribution(metric_name, options) do
    metric_name = validate_metric_or_event_name!(metric_name)
    {event_name, [measurement]} = Enum.split(metric_name, -1)
    {event_name, options} = Keyword.pop(options, :event_name, event_name)
    {measurement, options} = Keyword.pop(options, :measurement, measurement)
    event_name = validate_metric_or_event_name!(event_name)
    buckets = Keyword.fetch!(options, :buckets)
    validate_distribution_buckets!(buckets)
    validate_metric_options!(options)
    options = fill_in_default_metric_options(options)

    %Distribution{
      name: metric_name,
      event_name: event_name,
      measurement: measurement,
      tags: Keyword.fetch!(options, :tags),
      tag_values: options |> Keyword.fetch!(:tag_values) |> tag_values_spec_to_function(),
      buckets: buckets,
      description: Keyword.fetch!(options, :description),
      unit: Keyword.fetch!(options, :unit)
    }
  end

  # Helpers

  @spec validate_metric_or_event_name!(term()) :: [atom(), ...]
  defp validate_metric_or_event_name!(metric_or_event_name)
       when metric_or_event_name == [] or metric_or_event_name == "" do
    raise ArgumentError, "metric or event name can't be empty"
  end

  defp validate_metric_or_event_name!(metric_or_event_name) when is_list(metric_or_event_name) do
    if Enum.all?(metric_or_event_name, &is_atom/1) do
      metric_or_event_name
    else
      raise ArgumentError,
            "expected metric or event name to be a list of atoms or a string, got #{
              inspect(metric_or_event_name)
            }"
    end
  end

  defp validate_metric_or_event_name!(metric_or_event_name)
       when is_binary(metric_or_event_name) do
    segments = String.split(metric_or_event_name, ".")

    if Enum.any?(segments, &(&1 == "")) do
      raise ArgumentError,
            "metric or event name #{metric_or_event_name} contains leading, " <>
              "trailing or consecutive dots"
    end

    Enum.map(segments, &String.to_atom/1)
  end

  defp validate_metric_or_event_name!(term) do
    raise ArgumentError,
          "expected metric name to be a string or a list of atoms, got #{inspect(term)}"
  end

  @spec fill_in_default_metric_options([metric_option()]) :: [metric_option()]
  defp fill_in_default_metric_options(options) do
    Keyword.merge(default_metric_options(), options)
  end

  @spec default_metric_options() :: [metric_option()]
  defp default_metric_options() do
    [
      tags: [],
      tag_values: & &1,
      description: nil,
      unit: :unit
    ]
  end

  @spec validate_metric_options!([metric_option()]) :: :ok | no_return()
  defp validate_metric_options!(options) do
    if tags = Keyword.get(options, :tags), do: validate_tags!(tags)
    if tag_values = Keyword.get(options, :tag_values), do: validate_tag_values!(tag_values)
    if description = Keyword.get(options, :description), do: validate_description!(description)
    if unit = Keyword.get(options, :unit), do: validate_unit!(unit)
  end

  @spec validate_tags!(term()) :: :ok | no_return()
  defp validate_tags!(list) when is_list(list) do
    :ok
  end

  defp validate_tags!(term) do
    raise ArgumentError, "expected tag keys to be a list, got: #{inspect(term)}"
  end

  @spec validate_tag_values!(term()) :: :ok | no_return()
  defp validate_tag_values!(fun) when is_function(fun, 1) do
    :ok
  end

  defp validate_tag_values!(term) do
    raise ArgumentError,
          "expected tag_values fun to be a one-argument function, got: #{inspect(term)}"
  end

  @spec validate_description!(term()) :: :ok | no_return()
  defp validate_description!(term) do
    if String.valid?(term) do
      :ok
    else
      raise ArgumentError, "expected description to be a string, got #{inspect(term)}"
    end
  end

  @spec validate_unit!(term()) :: :ok | no_return()
  defp validate_unit!(unit) when is_atom(unit) do
    :ok
  end

  defp validate_unit!(term) do
    raise ArgumentError, "expected unit to be an atom, got #{inspect(term)}"
  end

  @spec validate_distribution_buckets!(term()) :: :ok | no_return()
  defp validate_distribution_buckets!([_ | _] = buckets) do
    unless Enum.all?(buckets, &is_number/1) do
      raise ArgumentError, "expected buckets to be a list of numbers, got #{inspect(buckets)}"
    end

    unless buckets == Enum.sort(buckets) do
      raise ArgumentError, "expected buckets to be ordered ascending, got #{inspect(buckets)}"
    end

    :ok
  end

  defp validate_distribution_buckets!(term) do
    raise ArgumentError, "expected buckets to be a non-empty list, got #{inspect(term)}"
  end

  @spec tag_values_spec_to_function(tag_values()) ::
          (:telemetry.event_metadata() -> :telemetry.event_metadata())
  defp tag_values_spec_to_function(fun), do: fun
end
