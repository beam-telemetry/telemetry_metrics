defmodule Telemetry.Metrics.TestHelpers do
  @moduledoc """
  Various utility function to be used in tests.
  """

  @doc """
  Returns a value of datapoint belonging to a measurement matching the given tagset.

  Returns `nil` if a datapoint can not be found.
  """
  @spec find_datapoint(
          [Telemetry.Metrics.measurement()],
          Telemetry.Metrics.datapoint_name(),
          Telemetry.Metrics.tagset()
        ) :: Telemetry.Metrics.datapoint_value() | nil
  def find_datapoint(measurements, datapoint_name, tagset) do
    case Enum.find(measurements, &(&1.tagset == tagset)) do
      %{datapoints: datapoints} ->
        Map.get(datapoints, datapoint_name)

      _ ->
        nil
    end
  end
end
