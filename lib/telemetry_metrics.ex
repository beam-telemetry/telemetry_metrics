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

  ## Metric specifications

  Metric specification is a data structure describing the metric - its name, type, name of the
  events aggregated by the metric, etc. The structure of metric specification is relevant only to
  authors of reporters.

  Metric specifications are created using one of the four functions: `counter/2`, `sum/2`,
  `last_value/2` and `distribution/2`. Each of those functions returns a specification of metric
  of the corresponding type. The first argument to all these functions is the name of events which
  are aggregated by the metric. The second argument is a list of options. Below is the description
  of the options common to all metric types:

  * `:name` - the metric name. Defaults to event name given as first argument;
  * `:tags_fun` - function called on every event, converting metadata to tags. Defaults to `nil`,
    which means that all, raw metadata should be treated as tags;
  * `:tag_keys` - tag keys by which aggregations will be broken down. Defaults to an empty
    list;
  * `:description` - human-readable description of the metric. Might be used by reporters for
    documentation purposes. Defaults to empty string;
  * `:unit` - the unit of event values. Might be used by reporters for documentation purposes.
    Defaults to `:unit`.

  ## Reporters

  Reporters take metric definitions as an input, subscribe to relevant events and update the metrics
  when the events are emitted. Updating the metric might involve publishing the metrics periodically,
  or on demand, to external systems. `Telemetry.Metrics` defines only specification for metric types,
  and reporters should provide actual implementation for these aggregations.

  ### Rationale

  The design proposed by `Telemetry.Metrics` might look controversial - unlike most of the libraries
  available on the BEAM, it doesn't aggregate metrics itself, it merely defines what users should
  expect when using the reporters. There are two arguments for this solution. However,
  if `Telemetry.Metrics` would aggregate metrics, the way those aggregations work would be imposed
  on the system where the metrics are published to. For example, counters in StatsD are reset on
  every flush and can be decremented, whereas counters in Prometheus are monotonically increasing.
  `Telemetry.Metrics` doesn't focus on those details - instead, it describes what the end user,
  operator, expects to see when using the metric of particular type. This implies that in most
  cases aggregated metrics won't be visible inside the BEAM, but in exchange aggregations can be
  implemented in a way that makes most sense for particular system. Finally, one could also
  implement an in-VM "reporter" which would aggregate the metrics and expose them inside the BEAM;
  When there is a need to swap the reporters, and if both reporters are following the metric types
  specification, then the end result of aggregation

  ### Requirements for reporters

  Reporters should accept metric specifications and subscribe to relevant events. When those events
  are emitted, metric should be updated (either in-memory or by contacting external system) in such
  a way that the user is able to view metric values as described in the "Metric types" section.

  If the reporter does not support the metric given to it, it should log a warning.

  Reporters should also document how `Telemetry.Metrics` metric types, names tags are translated to
  metric types and identifiers in the system they publish metrics to.
  """

  @type metric_name :: [atom(), ...]
  @type metric_type :: :counter | :sum | :last_value | :distribution
  @type tags_fun :: (Telemetry.event_metadata() -> %{tag_key => term()})
  @type tag_key :: atom()
  @type description :: String.t()
  @type unit :: atom()
  @type counter_options :: [metric_option()]
  @type sum_options :: [metric_option()]
  @type last_value_options :: [metric_option()]
  @type metric_option ::
          {:name, metric_name()}
          | {:tags_fun, tags_fun() | nil}
          | {:tag_keys, [tag_key()]}
          | {:description, description()}
          | {:unit, unit()}

  defmodule Metric do
    @moduledoc """
    A metric specification.

    This struct should be used by reporters to initialize the metric at runtime.
    """

    alias Telemetry.Metrics

    defstruct [:name, :type, :event_name, :tags_fun, :tag_keys, :description, :unit]

    @type t :: %__MODULE__{
            name: Metrics.metric_name(),
            type: Metrics.metric_type(),
            event_name: Telemetry.event_name(),
            tags_fun: Telemetry.Metrics.tags_fun() | nil,
            tag_keys: [Metrics.tag_key()],
            description: Metrics.description(),
            unit: Metrics.unit()
          }
  end

  # API

  @doc """
  Returns a specification of counter metric.

  See "Metric specifications" section in the top-level documentation of this module for more
  information.
  """
  @spec counter(Telemetry.event_name(), counter_options()) :: Metric.t()
  def counter(event_name, options) do
    validate_event_name!(event_name)
    options = Keyword.merge(default_metric_options(event_name), options)
    validate_metric_options!(options)

    %Metric{
      name: Keyword.fetch!(options, :name),
      type: :counter,
      event_name: event_name,
      tags_fun: Keyword.fetch!(options, :tags_fun),
      tag_keys: Keyword.fetch!(options, :tag_keys),
      description: Keyword.fetch!(options, :description),
      unit: Keyword.fetch!(options, :unit)
    }
  end

  @doc """
  Returns a specification of sum metric.

  See "Metric specifications" section in the top-level documentation of this module for more
  information.
  """
  @spec sum(Telemetry.event_name(), sum_options()) :: Metric.t()
  def sum(event_name, options) do
    validate_event_name!(event_name)
    options = Keyword.merge(default_metric_options(event_name), options)
    validate_metric_options!(options)

    %Metric{
      name: Keyword.fetch!(options, :name),
      type: :sum,
      event_name: event_name,
      tags_fun: Keyword.fetch!(options, :tags_fun),
      tag_keys: Keyword.fetch!(options, :tag_keys),
      description: Keyword.fetch!(options, :description),
      unit: Keyword.fetch!(options, :unit)
    }
  end

  @doc """
  Returns a specification of last value metric.

  See "Metric specifications" section in the top-level documentation of this module for more
  information.
  """
  @spec last_value(Telemetry.event_name(), last_value_options()) :: Metric.t()
  def last_value(event_name, options) do
    validate_event_name!(event_name)
    options = Keyword.merge(default_metric_options(event_name), options)
    validate_metric_options!(options)

    %Metric{
      name: Keyword.fetch!(options, :name),
      type: :last_value,
      event_name: event_name,
      tags_fun: Keyword.fetch!(options, :tags_fun),
      tag_keys: Keyword.fetch!(options, :tag_keys),
      description: Keyword.fetch!(options, :description),
      unit: Keyword.fetch!(options, :unit)
    }
  end

  # Helpers

  @spec validate_event_name!(term()) :: :ok | no_return()
  defp validate_event_name!(list) when is_list(list) do
    if Enum.all?(list, &is_atom/1) do
      :ok
    else
      raise ArgumentError, "Expected event name to be a list of atoms, got: #{inspect(list)}"
    end
  end

  defp validate_event_name!(term) do
    raise ArgumentError, "Expected event name to be a list of atoms, got: #{inspect(term)}"
  end

  @spec default_metric_options(Telemetry.event_name()) :: [metric_option()]
  defp default_metric_options(event_name) do
    [
      name: event_name,
      tags_fun: nil,
      tag_keys: [],
      description: "",
      unit: :unit
    ]
  end

  @spec validate_metric_options!([metric_option()]) :: :ok | no_return()
  defp validate_metric_options!(options) do
    metric_name = Keyword.fetch!(options, :name)
    tags_fun = Keyword.fetch!(options, :tags_fun)
    tag_keys = Keyword.fetch!(options, :tag_keys)
    description = Keyword.fetch!(options, :description)
    unit = Keyword.fetch!(options, :unit)

    validate_metric_name!(metric_name)
    validate_tags_fun!(tags_fun)
    validate_tag_keys!(tag_keys)
    validate_description!(description)
    validate_unit!(unit)
  end

  @spec validate_metric_name!(term()) :: :ok | no_return()
  defp validate_metric_name!([_ | _] = list) do
    if Enum.all?(list, &is_atom/1) do
      :ok
    else
      raise ArgumentError,
            "Expected metric name to be a non empty list of atoms, got: #{inspect(list)}"
    end
  end

  defp validate_metric_name!(term) do
    raise ArgumentError,
          "Expected metric name to be a non empty list of atoms, got: #{inspect(term)}"
  end

  @spec validate_tags_fun!(term()) :: :ok | no_return()
  defp validate_tags_fun!(fun) when is_function(fun, 1) do
    :ok
  end

  defp validate_tags_fun!(fun) when is_function(fun) do
    {:arity, arity} = :erlang.fun_info(fun, :arity)

    raise ArgumentError,
          "Expected tags fun to be a one-argument function, but the arity is #{arity}"
  end

  defp validate_tags_fun!(nil) do
    :ok
  end

  defp validate_tags_fun!(term) do
    raise ArgumentError, "Expected tags fun to be a function or nil, got: #{inspect(term)}"
  end

  @spec validate_tag_keys!(term()) :: :ok | no_return()
  defp validate_tag_keys!(list) when is_list(list) do
    if Enum.all?(list, &is_atom/1) do
      :ok
    else
      raise ArgumentError, "Expected tag keys to be a list of atoms, got: #{inspect(list)}"
    end
  end

  defp validate_tag_keys!(term) do
    raise ArgumentError, "Expected tag keys to be a list of atoms, got: #{inspect(term)}"
  end

  @spec validate_description!(term()) :: :ok | no_return()
  defp validate_description!(term) do
    if String.valid?(term) do
      :ok
    else
      raise ArgumentError, "Expected description to be a string, got #{inspect(term)}"
    end
  end

  @spec validate_unit!(term()) :: :ok | no_return()
  defp validate_unit!(unit) when is_atom(unit) do
    :ok
  end

  defp validate_unit!(term) do
    raise ArgumentError, "Expected unit to be an atom, got #{inspect(term)}"
  end
end
