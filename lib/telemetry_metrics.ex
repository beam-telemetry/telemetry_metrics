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

      Telemetry.execute([:http, :request], 1, %{controller: "user_controller", action: "index"})
      Telemetry.execute([:http, :request], 1, %{controller: "user_controller", action: "index"})
      Telemetry.execute([:http, :request], 1, %{controller: "user_controller", action: "create"})
      Telemetry.execute([:http, :request], 1, %{controller: "product_controller", action: "get"})

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
  of the corresponding type. The first argument to all these functions is the name of events which
  are aggregated by the metric. Event name might be represented as in Telemetry, i.e. as a list of
  atoms (`[:http, :request]`), or as a string of words joined by dots (`"http.request"`).

  > Note: do not use data from external sources as metric or event names! Since they are converted
  > to atoms, your application becomes vulnerable to atom leakage and might run out of memory.

  The second argument is a list of options. Below is the description of the options common to all
  metric types:

  * `:name` - the metric name. Metric name can be represented in the same way as event name.
    Defaults to event name given as first argument;
  * `:tags` - tags by which aggregations will be broken down. Defaults to an empty list;
  * `:metadata` - determines what part of event metadata is used as the source of tag values.
    Default value is an empty list. Note that the specified metadata should contain at least those
    keys which are set as `:tags`. There are three possible values of this option:
    * `:all` - all event metadata is used;
    * list of terms, e.g. `[:table, :kind]` - only these keys from the event metadata are used;
    * one argument function taking the event metadata and returning the metadata which should be
      used to generate tag values
  * `:description` - human-readable description of the metric. Might be used by reporters for
    documentation purposes. Defaults to `nil`;
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
  expect when using the reporters. There are two arguments for this solution.
  if `Telemetry.Metrics` would aggregate metrics, the way those aggregations work would be imposed
  on the system where the metrics are published to. For example, counters in StatsD are reset on
  every flush and can be decremented, whereas counters in Prometheus are monotonically increasing.
  `Telemetry.Metrics` doesn't focus on those details - instead, it describes what the end user,
  operator, expects to see when using the metric of particular type. This implies that in most
  cases aggregated metrics won't be visible inside the BEAM, but in exchange aggregations can be
  implemented in a way that makes most sense for particular system. Finally, one could also
  implement an in-VM "reporter" which would aggregate the metrics and expose them inside the BEAM.
  When there is a need to swap the reporters, and if both reporters are following the metric types
  specification, then the end result of aggregation is the same, regardless of the backend system
  in use.

  ### Requirements for reporters

  Reporters should accept metric specifications and subscribe to relevant events. When those events
  are emitted, metric should be updated (either in-memory or by contacting external system) in such
  a way that the user is able to view metric values as described in the "Metric types" section.

  If the reporter does not support the metric given to it, it should log a warning.

  Reporters should also document how `Telemetry.Metrics` metric types, names tags are translated to
  metric types and identifiers in the system they publish metrics to.
  """

  require Logger

  alias Telemetry.Metrics.{Counter, Sum, LastValue, Distribution}

  @type event_name :: String.t() | Telemetry.event_name()
  @type metric_name :: String.t() | normalized_metric_name()
  @type normalized_metric_name :: [atom(), ...]
  @type metric_type :: :counter | :sum | :last_value | :distribution
  @type metadata ::
          :all | [key :: term()] | (Telemetry.event_metadata() -> Telemetry.event_metadata())
  @type tag :: term()
  @type tags :: [tag()]
  @type description :: nil | String.t()
  @type unit :: atom()
  @type counter_options :: [metric_option()]
  @type sum_options :: [metric_option()]
  @type last_value_options :: [metric_option()]
  @type distribution_options :: [metric_option() | {:buckets, Distribution.buckets()}]
  @type metric_option ::
          {:name, metric_name()}
          | {:metadata, metadata()}
          | {:tags, tags()}
          | {:description, description()}
          | {:unit, unit()}

  @typedoc """
  Common fields for metric specifications

  Reporters should assume that these fields are present in all metric specifications.
  """
  @type t :: %{
          __struct__: module(),
          name: normalized_metric_name(),
          type: metric_type(),
          event_name: Telemetry.event_name(),
          metadata: (Telemetry.event_metadata() -> Telemetry.event_metadata()),
          tags: tags(),
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
        "http.request",
        metadata: [:controller, :action] tags: [:controller, :action]
      )
  """
  @spec counter(event_name(), counter_options()) :: Counter.t()
  def counter(event_name, options \\ []) do
    {metric_name, options} = Keyword.pop(options, :name, event_name)
    event_name = validate_event_or_metric_name!(event_name)
    metric_name = validate_event_or_metric_name!(metric_name)
    validate_metric_options!(options)
    options = Keyword.merge(default_metric_options(), options)

    %Counter{
      name: metric_name,
      event_name: event_name,
      metadata: options |> Keyword.fetch!(:metadata) |> metadata_spec_to_function(),
      tags: Keyword.fetch!(options, :tags),
      description: Keyword.fetch!(options, :description),
      unit: Keyword.fetch!(options, :unit)
    }
  end

  @doc """
  Returns a specification of sum metric.

  See "Metric specifications" section in the top-level documentation of this module for more
  information.

  ## Example

      sum("user.session_count.change", name: "user.session_count", metadata: [:role], tags: [:role])
  """
  @spec sum(event_name(), sum_options()) :: Sum.t()
  def sum(event_name, options \\ []) do
    {metric_name, options} = Keyword.pop(options, :name, event_name)
    event_name = validate_event_or_metric_name!(event_name)
    metric_name = validate_event_or_metric_name!(metric_name)
    validate_metric_options!(options)
    options = Keyword.merge(default_metric_options(), options)

    %Sum{
      name: metric_name,
      event_name: event_name,
      metadata: options |> Keyword.fetch!(:metadata) |> metadata_spec_to_function(),
      tags: Keyword.fetch!(options, :tags),
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
  @spec last_value(event_name(), last_value_options()) :: LastValue.t()
  def last_value(event_name, options \\ []) do
    {metric_name, options} = Keyword.pop(options, :name, event_name)
    event_name = validate_event_or_metric_name!(event_name)
    metric_name = validate_event_or_metric_name!(metric_name)
    validate_metric_options!(options)
    options = Keyword.merge(default_metric_options(), options)

    %LastValue{
      name: metric_name,
      event_name: event_name,
      metadata: options |> Keyword.fetch!(:metadata) |> metadata_spec_to_function(),
      tags: Keyword.fetch!(options, :tags),
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
        "http.request",
        buckets: [100, 200, 300],
        metadata: [:controller, :action],
        tags: [:controller, :action],
      )
  """
  @spec distribution(event_name(), distribution_options()) :: Distribution.t()
  def distribution(event_name, options) do
    {metric_name, options} = Keyword.pop(options, :name, event_name)
    event_name = validate_event_or_metric_name!(event_name)
    metric_name = validate_event_or_metric_name!(metric_name)
    buckets = Keyword.fetch!(options, :buckets)
    validate_distribution_buckets!(buckets)
    validate_metric_options!(options)
    options = Keyword.merge(default_metric_options(), options)

    %Distribution{
      name: metric_name,
      event_name: event_name,
      metadata: options |> Keyword.fetch!(:metadata) |> metadata_spec_to_function(),
      tags: Keyword.fetch!(options, :tags),
      buckets: buckets,
      description: Keyword.fetch!(options, :description),
      unit: Keyword.fetch!(options, :unit)
    }
  end

  # Helpers

  @spec validate_event_or_metric_name!(term()) ::
          normalized_metric_name() | Telemetry.event_name() | no_return()
  defp validate_event_or_metric_name!(list) when is_list(list) do
    if Enum.all?(list, &is_atom/1) do
      list
    else
      raise ArgumentError,
            "expected event or metric name to be a list of atoms or a string, " <>
              "got #{inspect(list)}"
    end
  end

  defp validate_event_or_metric_name!(event_or_metric_name)
       when is_binary(event_or_metric_name) do
    segments = String.split(event_or_metric_name, ".")

    if Enum.any?(segments, &(&1 == "")) do
      Logger.warn(fn ->
        "Event or metric name #{event_or_metric_name} contains leading, trailing or " <>
          "consecutive dots"
      end)
    end

    Enum.map(segments, &String.to_atom/1)
  end

  defp validate_event_or_metric_name!(term) do
    raise ArgumentError,
          "expected event or metric name to be a list of atoms or a string, " <>
            "got #{inspect(term)}"
  end

  @spec default_metric_options() :: [metric_option()]
  defp default_metric_options() do
    [
      metadata: [],
      tags: [],
      description: nil,
      unit: :unit
    ]
  end

  @spec validate_metric_options!([metric_option()]) :: :ok | no_return()
  defp validate_metric_options!(options) do
    if metadata = Keyword.get(options, :metadata), do: validate_metadata!(metadata)
    if tags = Keyword.get(options, :tags), do: validate_tags!(tags)
    if description = Keyword.get(options, :description), do: validate_description!(description)
    if unit = Keyword.get(options, :unit), do: validate_unit!(unit)
  end

  @spec validate_metadata!(term()) :: :ok | no_return()
  defp validate_metadata!(fun) when is_function(fun, 1) do
    :ok
  end

  defp validate_metadata!(fun) when is_function(fun) do
    {:arity, arity} = :erlang.fun_info(fun, :arity)

    raise ArgumentError,
          "expected metadata fun to be a one-argument function, but the arity is #{arity}"
  end

  defp validate_metadata!(:all) do
    :ok
  end

  defp validate_metadata!(list) when is_list(list) do
    :ok
  end

  defp validate_metadata!(term) do
    raise ArgumentError,
          "expected metadata to be an atom :all, a list or a function, got #{inspect(term)}"
  end

  @spec validate_tags!(term()) :: :ok | no_return()
  defp validate_tags!(list) when is_list(list) do
    :ok
  end

  defp validate_tags!(term) do
    raise ArgumentError, "expected tag keys to be a list, got: #{inspect(term)}"
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

  @spec metadata_spec_to_function(metadata()) ::
          (Telemetry.event_metadata() -> Telemetry.event_metadata())
  defp metadata_spec_to_function(:all), do: & &1
  defp metadata_spec_to_function([]), do: fn _ -> %{} end
  defp metadata_spec_to_function(keys) when is_list(keys), do: &Map.take(&1, keys)
  defp metadata_spec_to_function(fun), do: fun
end
