defmodule Telemetry.Metrics.LastValue do
  @moduledoc """
  Defines a specification of last value metric.
  """

  alias Telemetry.Metrics

  defstruct [:name, :event_name, :measurement, :metadata, :tags, :description, :unit]

  @type t :: %__MODULE__{
          name: Metrics.normalized_metric_name(),
          event_name: :telemetry.event_name(),
          measurement: (:telemetry.event_measurements() -> number()),
          metadata: (:telemetry.event_metadata() -> :telemetry.event_metadata()),
          tags: Metrics.tags(),
          description: Metrics.description(),
          unit: Metrics.unit()
        }
end
