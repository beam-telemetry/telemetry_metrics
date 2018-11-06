defmodule Telemetry.Metrics.Metric do
  @moduledoc """
  Defines common fields for metric specifications

  Reporters should assume that these fields are present in all metric specifications.
  """

  alias Telemetry.Metrics

  @type t :: %{
          __struct__: module(),
          name: Metrics.normalize_metric_name(),
          type: Metrics.metric_type(),
          event_name: Telemetry.event_name(),
          metadata: (Telemetry.event_metadata() -> Telemetry.event_metadata()),
          tags: Metrics.tags(),
          description: Metrics.description(),
          unit: Metrics.unit()
        }
end
