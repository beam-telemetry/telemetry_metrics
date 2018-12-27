defmodule Telemetry.Metrics.Distribution do
  @moduledoc """
  Defines a specification of distribution metric.
  """

  alias Telemetry.Metrics

  defstruct [:name, :event_name, :metadata, :tags, :buckets, :description, :unit]

  @typedoc """
  Distribution metric bucket boundaries.

  Bucket boundaries are represented by a non-empty list of increasing numbers.

  ## Examples

      [0, 100, 200, 300]
      # Buckets: [-inf, 0], [0, 100], [100, 200], [200, 300], [300, +inf]

      [99.9]
      # Buckets: [-inf, 99.9], [99.9, +inf]
  """
  @type buckets :: [number(), ...]

  @type t :: %__MODULE__{
          name: Metrics.normalized_metric_name(),
          event_name: Telemetry.event_name(),
          metadata: (Telemetry.event_metadata() -> Telemetry.event_metadata()),
          tags: Metrics.tags(),
          buckets: buckets(),
          description: Metrics.description(),
          unit: Metrics.unit()
        }
end
