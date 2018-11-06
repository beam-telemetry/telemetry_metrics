defmodule Telemetry.Metrics.Sum do
  @moduledoc """
  Defines a specification of sum metric.
  """

  defstruct [:name, :event_name, :metadata, :tags, :description, :unit]

  @type t :: %__MODULE__{
          name: Metrics.metric_name(),
          event_name: Telemetry.event_name(),
          metadata: (Telemetry.event_metadata() -> Telemetry.event_metadata()),
          tags: Metrics.tags(),
          description: Metrics.description(),
          unit: Metrics.unit()
        }
end
