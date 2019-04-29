defmodule Telemetry.Metrics do
  @moduledoc """
  Common interface for defining metrics based on
  [`:telemetry`](https://github.com/beam-telemetry/telemetry) events.

  Metrics are aggregations of Telemetry events with specific name, providing a view of the
  system's behaviour over time.

  For example, to build a sum of HTTP request payload size received by your system, you could define
  a following metric:

      sum("http.request.payload_size")

  This definition means that the metric is based on `[:http, :request]` events, and it should sum up
  values under `:payload_size` key in events' measurements.

  Telemetry.Metrics also supports breaking down the metric values by tags - this means that there
  will be a distinct metric for each unique set of selected tags found in event metadata:

      sum("http.request.payload_size", tags: [:host, :method])

  The above definiton means that we want to keep track of the sum, but for each unique pair of
  request host and method (assuming that `:host` and `:method` keys are present in event's metadata).

  There are four metric types provided by Telemetry.Metrics:
    * `counter/2` which counts the total number of emitted events
    * `sum/2` which keeps track of the sum of selected measurement
    * `last_value/2` holding the value of the selected measurement from the most recent event
    * `summary/2` calculating statistics of the selected measurement, like maximum, mean,
      percentiles etc.
    * `distribution/2` which builds a histogram of selected measurement

  Note that these metric definitions by itself are not enough, as they only provide the specification
  of what is the expected end-result. The job of subscribing to events and building the actual
  metrics is a responsibility of reporters (described in the "Reporters" section).

  ## Metric definitions

  Metric definition is a data structure describing the metric - its name, type, name of the
  events aggregated by the metric, etc. The structure of metric definition is relevant only to
  authors of reporters.

  Metric definitions are created using one of the four functions: `counter/2`, `sum/2`, `last_value/2`
  and `distribution/2`. Each of those functions returns a definition of metric of the corresponding
  type.

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
    * `:tags` - a subset of metadata keys by which aggregations will be broken down. Defaults to
      an empty list.
    * `:tag_values` - a function that receives the metadata and returns a map with the tags as keys
      and their respective values. Defaults to returning the metadata itself.
    * `:description` - human-readable description of the metric. Might be used by reporters for
      documentation purposes. Defaults to `nil`.
    * `:unit` - an atom describing the unit of selected measurement or a tuple indicating that a
      measurement should be converted from one unit to another before a metric is updated. Currently,
      only time unit conversions are supported. For example, setting this option to
      `{:native, :millisecond}` means that the measurements are provided in the `:native` time unit
      (you can read more about it in the documentation for `System.convert_time_unit/3`), but a metric
      should have its values in milliseconds. Both elements of the conversion tuple need to be of
      type `t:time_unit/0`.

  ## Reporters

  Reporters take metric definitions as an input, subscribe to relevant events and update the metrics
  when the events are emitted. Updating the metric might involve publishing the metrics periodically,
  or on demand, to external systems. `Telemetry.Metrics` defines only how metrics of particular type
  should behave and reporters should provide actual implementation for these aggregations.

  `Telemetry.Metrics` package does not include any reporter itself.
  """

  require Logger

  alias Telemetry.Metrics.{Counter, Sum, LastValue, Summary, Distribution}

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
  @type unit_conversion() :: {time_unit(), time_unit()}
  @type time_unit() :: :second | :millisecond | :microsecond | :nanosecond | :native
  @type counter_options :: [metric_option()]
  @type sum_options :: [metric_option()]
  @type last_value_options :: [metric_option()]
  @type summary_options :: [metric_option()]
  @type distribution_options :: [metric_option() | {:buckets, Distribution.buckets()}]
  @type metric_option ::
          {:event_name, :telemetry.event_name()}
          | {:measurement, measurement()}
          | {:tags, tags()}
          | {:tag_values, tag_values()}
          | {:description, description()}
          | {:unit, unit() | unit_conversion()}

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
  Returns a definition of counter metric.

  Counter metric keeps track of the total number of specific events emitted.

  Note that for the counter metric it doesn't matter what measurement is selected, as it is
  ignored by reporters anyway.

  See the "Metric definitions" section in the top-level documentation of this module for more
  information.

  ## Example

      counter(
        "http.request.count",
        tags: [:controller, :action]
      )
  """
  @spec counter(metric_name(), counter_options()) :: Counter.t()
  def counter(metric_name, options \\ []) do
    struct(Counter, common_fields(metric_name, options))
  end

  @doc """
  Returns a definition of sum metric.

  Sum metric keeps track of the sum of selected measurement's values carried by specific events.

  See the "Metric definitions" section in the top-level documentation of this module for more
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
    struct(Sum, common_fields(metric_name, options))
  end

  @doc """
  Returns a definition of last value metric.

  Last value keeps track of the selected measurement found in the most recent event.

  See the "Metric definitions" section in the top-level documentation of this module for more
  information.

  ## Example

      last_value(
        "vm.memory.total",
        description: "Total amount of memory allocated by the Erlang VM", unit: :byte
      )
  """
  @spec last_value(metric_name(), last_value_options()) :: LastValue.t()
  def last_value(metric_name, options \\ []) do
    struct(LastValue, common_fields(metric_name, options))
  end

  @doc """
  Returns a definition of summary metric.

  This metric aggregates measurement's values into statistics, e.g. minimum and maximum, mean, or
  percentiles. It is up to the reporter to decide which statistics exactly are exposed.

  See the "Metric definitions" section in the top-level documentation of this module for more
  information.

  ## Example

      summary(
        "db.query.duration",
        tags: [:table],
        unit: {:native, :millisecond}
      )
  """
  @spec summary(metric_name(), summary_options()) :: Summary.t()
  def summary(metric_name, options \\ []) do
    struct(Summary, common_fields(metric_name, options))
  end

  @doc """
  Returns a definition of distribution metric.

  Distribution metric builds a histogram of selected measurement's values. Because of that, it is
  required that you specify the histograms buckets via `:buckets` option.

  For example, given `buckets: [0, 100, 200]`, the distribution metric produces four values:
    * number of measurements less than or equal to 0
    * number of measurements greater than 0 and less than or equal to 100
    * number of measurements greater than 100 and less than or equal to 200
    * number of measurements greater than 200

  See the "Metric definitions" section in the top-level documentation of this module for more
  information.

  ## Example

      distribution(
        "http.request.duration",
        buckets: [100, 200, 300],
        tags: [:controller, :action],
      )
  """
  @spec distribution(metric_name(), distribution_options()) :: Distribution.t()
  def distribution(metric_name, options) do
    fields = common_fields(metric_name, options)
    buckets = Keyword.fetch!(options, :buckets)
    validate_distribution_buckets!(buckets)
    struct(Distribution, Map.put(fields, :buckets, buckets))
  end

  # Helpers

  @spec common_fields(metric_name(), [metric_option() | {atom(), term()}]) :: map()
  defp common_fields(metric_name, options) do
    metric_name = validate_metric_or_event_name!(metric_name)
    {event_name, [measurement]} = Enum.split(metric_name, -1)
    {event_name, options} = Keyword.pop(options, :event_name, event_name)
    {measurement, options} = Keyword.pop(options, :measurement, measurement)
    event_name = validate_metric_or_event_name!(event_name)
    {unit, options} = Keyword.pop(options, :unit, :unit)
    {unit, conversion_ratio} = validate_unit!(unit)
    measurement = maybe_convert_measurement(measurement, conversion_ratio)
    validate_metric_options!(options)

    options
    |> fill_in_default_metric_options()
    |> Map.new()
    |> Map.merge(%{
      name: metric_name,
      event_name: event_name,
      measurement: measurement,
      unit: unit
    })
  end

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
      description: nil
    ]
  end

  @spec validate_metric_options!([metric_option()]) :: :ok | no_return()
  defp validate_metric_options!(options) do
    if tags = Keyword.get(options, :tags), do: validate_tags!(tags)
    if tag_values = Keyword.get(options, :tag_values), do: validate_tag_values!(tag_values)
    if description = Keyword.get(options, :description), do: validate_description!(description)
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

  @spec maybe_convert_measurement(measurement(), conversion_ratio :: non_neg_integer()) ::
          measurement()
  defp maybe_convert_measurement(measurement, 1) do
    # Don't wrap measurement if no conversion is required.
    measurement
  end

  defp maybe_convert_measurement(measurement, conversion_ratio)
       when is_function(measurement, 1) do
    fn measurements ->
      measurement.(measurements) * conversion_ratio
    end
  end

  defp maybe_convert_measurement(measurement, conversion_ratio) do
    fn measurements ->
      measurements[measurement] * conversion_ratio
    end
  end

  @spec validate_unit!(term()) :: {unit(), conversion_ratio :: number()} | no_return()
  defp validate_unit!({from_unit, to_unit} = t) do
    if time_unit?(from_unit) and time_unit?(to_unit) do
      {to_unit, conversion_ratio(from_unit, to_unit)}
    else
      raise ArgumentError,
            "expected both elements of the unit conversion tuple" <>
              "to represent time units, got #{inspect(t)}"
    end
  end

  defp validate_unit!(unit) when is_atom(unit) do
    {unit, 1}
  end

  defp validate_unit!(term) do
    raise ArgumentError,
          "expected unit to be an atom or a two-element tuple, got #{inspect(term)}"
  end

  # Maybe warn or raise if the result of conversion is 0?
  @spec conversion_ratio(time_unit(), time_unit()) :: number()
  defp conversion_ratio(unit, unit), do: 1

  defp conversion_ratio(from_unit, to_unit) do
    case System.convert_time_unit(1, from_unit, to_unit) do
      0 ->
        1 / System.convert_time_unit(1, to_unit, from_unit)

      ratio ->
        ratio
    end
  end

  @spec time_unit?(term()) :: boolean()
  defp time_unit?(:native), do: true
  defp time_unit?(:second), do: true
  defp time_unit?(:millisecond), do: true
  defp time_unit?(:microsecond), do: true
  defp time_unit?(:nanosecond), do: true
  defp time_unit?(_), do: false

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
end
