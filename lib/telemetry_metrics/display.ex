defmodule Telemetry.Metrics.Display do
  @moduledoc """
  Module implementing an API for displaying measurements in the console.
  """

  alias Telemetry.Metrics
  alias Telemetry.Metrics.Registry

  ## API

  @spec display(Registry.registry()) :: :ok
  def display(registry) do
    registry
    |> collect_measurements()
    |> Enum.map(fn {metric_name, measurements} ->
      format_metric_and_measurements(metric_name, measurements)
    end)
    |> Enum.join("\n")
    |> IO.puts()
  end

  ## Helpers

  @spec collect_measurements(Registry.registry()) :: [
          {Metrics.metric_name(), [Metrics.measurment()]}
        ]
  defp collect_measurements(registry) do
    registry
    |> Registry.get_metric_names()
    |> Enum.map(fn metric_name ->
      {:ok, measurements} = Registry.collect(registry, metric_name)
      {metric_name, measurements}
    end)
  end

  @spec format_metric_and_measurements(Metrics.metric_name(), [Metrics.measurement()]) ::
          String.t()
  defp format_metric_and_measurements(metric_name, measurements) do
    banner = """
    ################################################################################
    Metric #{inspect(metric_name)}
    ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    """

    formatted_measurements =
      measurements
      |> Enum.map(fn %{tagset: tagset, datapoints: datapoints} ->
        formatted_tagset =
          tagset
          |> Enum.map(fn {tag_key, tag_value} ->
            "#{tag_key}: #{tag_value}"
          end)
          |> Enum.join(", ")

        formatted_datapoints =
          datapoints
          |> Enum.map(fn {datapoint_key, datapoint_value} ->
            "#{datapoint_key}: #{datapoint_value}"
          end)
          |> Enum.join(", ")

        """
        Tagset -- #{formatted_tagset}
        Datapoints -- #{formatted_datapoints}
        """
      end)
      |> Enum.join(
        "--------------------------------------------------------------------------------\n"
      )

    banner <> formatted_measurements
  end
end
