defmodule Telemetry.Metrics.MetricDefinition do
  @moduledoc false
  # Struct describing the metric to be registered in the registry.

  alias Telemetry.Metrics.Metric.Counter

  @opaque t() :: %__MODULE__{
            metric_name: Telemetry.Metrics.metric_name(),
            event_name: Telemetry.event_name(),
            tags: [Telemetry.Metrics.tag_key()],
            callback_module: module(),
            metric_opts: term()
          }

  defstruct [:metric_name, :event_name, :tags, :callback_module, :metric_opts]

  ## API

  @spec new(
          Telemetry.Metrics.metric_name(),
          Telemetry.Metrics.metric_type(),
          Telemetry.event_name(),
          [Telemetry.Metrics.tag_key()],
          metric_options :: term()
        ) :: t()
  def new(metric_name, metric_type, event_name, tags, metric_opts) do
    callback_module =
      case metric_type do
        :counter ->
          Counter

        _ ->
          raise ArgumentError, "Unknown metric type: #{inspect(metric_type)}"
      end

    %__MODULE__{
      metric_name: metric_name,
      event_name: event_name,
      tags: tags,
      callback_module: callback_module,
      metric_opts: metric_opts
    }
  end
end
