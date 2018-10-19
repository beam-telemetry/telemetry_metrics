defmodule Telemetry.Metrics.UpdateEventHandler do
  # Telemetry event handler updating the metric.

  alias Telemetry.Metrics.Registry

  def handle_event(_event_name, event_value, event_metadata, config) do
    metric_state = Registry.get_metric_state(config.registry, config.metric_name)
    # TODO: Make it more efficient.
    # TODO: Handle string conversion failure and incomplete tagset.
    tagset =
      event_metadata
      |> Map.take(config.tags)
      |> Enum.map(fn {tag_key, value} -> {tag_key, to_string(value)} end)
      |> Enum.into(%{})

    new_metric_state = config.callback_module.update(event_value, tagset, metric_state)
    Registry.set_metric_state(config.registry, config.metric_name, new_metric_state)
  end
end
