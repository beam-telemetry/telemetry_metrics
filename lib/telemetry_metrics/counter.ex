defmodule Telemetry.Metrics.Counter do
  @moduledoc """
  Defines a specification of counter metric.
  """

  alias Telemetry.Metrics

  defstruct [:name, :event_name, :metadata, :tags, :description, :unit]

  @type t :: %__MODULE__{
          name: Metrics.normalized_metric_name(),
          event_name: :telemetry.event_name(),
          metadata: (:telemetry.event_metadata() -> :telemetry.event_metadata()),
          tags: Metrics.tags(),
          description: Metrics.description(),
          unit: Metrics.unit()
        }
end
