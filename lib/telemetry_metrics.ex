defmodule Telemetry.Metrics do
  @moduledoc """
  Allows to collect and aggregate Telemetry events over time.

  Metric is an entity transforming a stream of Telemetry events into aggregated values called
  datapoints. A single metric may produce multiple datapoints, e.g. a counter could report a total
  number of events it captured as well as number of events emitted during one minute long sliding
  window.

  ## Data model

  Telemetry metrics provide a multi-dimensional data model. This means that a metric produces
  multiple sets of datapoints, each set being bound to a unique set of tag values. But what does it
  mean in practice?

  Let's consider the counter metric. Imagine that you need to count a number of database queries,
  broken down by the kind of query (`insert`, `delete` etc.) and a table the query is made against.
  In some metric systems or libraries, you would need to define a metric for each kind of operation
  and each table. With Telemetry, only one metric is required, and tags can be used to further break
  down the datapoinst. Let's define such metric:

      definition = Telemetry.Metrics.new(:counter, [:db, :query], tags: [:table, :kind])

  In order for metric to actually work you need to register it first, but let's skip this
  step for now. Once the metric is up and running, we can start emitting the events:

      Telemetry.execute([:db, :query], 1, %{kind: :insert, table: "users"})
      Telemetry.execute([:db, :query], 1, %{kind: :select, table: "products"})
      Telemetry.execute([:db, :query], 1, %{kind: :select, table: "users"})
      Telemetry.execute([:db, :query], 1, %{kind: :select, table: "users"})

  And the values produced by the metric look as follows:

  | `table` | `kind`  | `total`  | `window`  |
  |---|---|---|---|
  | "users" | "insert"  | 1 | 1 |
  | "users" | "select" | 2 | 2 |
  | "products" | "select" | 1 | 1 |

  You can see that there is a row in the table above for each distinct set of tag values -
  a **tagset** - and each row has values for two datapoints: `total` and `window`. Each row in the
  table is called a **measurement**. Measurements are nothing more than values of datapoints grouped
  by tagset.

  ### Tagsets

  Tagsets are derived from events used by the metric. By default, values under tag keys are taken
  from event metadata and converted to strings, but you can also provide your own function
  translating event metadata into a tagset.
  """

  alias Telemetry.Metrics.MetricDefinition

  @type metric_name :: [atom(), ...]
  @type metric_type :: :counter
  @type tag_key :: atom()
  @type tag_value :: String.t()
  @type tagset :: %{tag_key() => tag_value()}
  @type datapoint_name :: atom()
  @type datapoint_value :: number()
  @type datapoints :: %{datapoint_name => datapoint_value}
  @type measurement :: %{tagset: tagset(), datapoints: datapoints()}
  @type option :: {:name, metric_name()} | {:tags, [tag_key()]}
  @type options :: [option()]
  @opaque metric_definition :: MetricDefinition.t()

  ## API

  @doc """
  Returns the metric definition which can be registered in the registry.

  In Telemetry, four values are required to define a metric:
  * Type which determines what datapoints will be produced;
  * Event whose values are to be aggregated by the metric;
  * Name uniquely identifying the metric the scope of a single registry;
  * Tags which are used to group datapoints

  By default, the name of the metric is the name of the event and the metric is using no tags.
  `metric_opts` are passed to the metric upon initialization.
  """
  @spec new(metric_type(), Telemetry.event_name(), options(), metric_options :: term()) ::
          metric_definition()
  def new(metric_type, event_name, opts \\ [], metric_opts \\ []) do
    metric_name = Keyword.get(opts, :name, event_name)
    tags = Keyword.get(opts, :tags, [])

    assert_list_of_atoms!(event_name)
    assert_list_of_atoms!(metric_name)
    assert_list_of_atoms!(tags)

    MetricDefinition.new(metric_name, metric_type, event_name, tags, metric_opts)
  end

  ## Helpers

  @spec assert_list_of_atoms!(term()) :: :ok | no_return()
  defp assert_list_of_atoms!(list) when is_list(list) do
    Enum.all?(list, &is_atom/1) or raise ArgumentError
    :ok
  end

  defp assert_list_of_atoms!(_) do
    raise ArgumentError
  end
end
