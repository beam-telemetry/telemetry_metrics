defmodule Telemetry.Metrics.Registry do
  # TODO: Consider changing a name, "Registry" will be confused with Elixir's
  # Registry.
  @moduledoc """
  Instantiates and groups metrics.
  """

  use GenServer

  alias Telemetry.Metrics

  @type registry :: GenServer.name()

  ## API

  @doc """
  Starts the registry with given name and links it to the calling process.
  """
  @spec start_link(registry, [Metrics.metric_definition()]) :: GenServer.on_start()
  def start_link(registry, definitions) do
    assert_unique_definitions!(definitions)
    GenServer.start_link(__MODULE__, [registry, definitions], name: registry)
  end

  @doc """
  Returns the names of all metrics registered in the registry.
  """
  @spec get_metric_names(registry) :: [Metrics.metric_name()]
  def get_metric_names(registry) do
    GenServer.call(registry, :get_metric_names)
  end

  @doc """
  Collects and returns the measurements produced by specific metric.

  Returns `{:error, :not_found}` when metric with given name is not registered.
  """
  @spec collect(registry, Metrics.metric_name()) ::
          {:ok, [Metric.measurement()]} | {:error, :not_found}
  def collect(registry, metric_name) do
    GenServer.call(registry, {:collect, metric_name})
  end

  ## Used by event handler

  # Saves the metric state after an update.
  @spec set_metric_state(registry, Metrics.metric_name(), Metrics.Metric.state()) :: :ok
  def set_metric_state(registry, metric_name, state) do
    :ets.insert(state_table_name(registry), {metric_name, state})
    :ok
  end

  # Retrieves the metric state to perform an update.
  @spec get_metric_state(registry, Metrics.metric_name()) :: Metrics.Metric.state()
  def get_metric_state(registry, metric_name) do
    [{_, state}] = :ets.lookup(state_table_name(registry), metric_name)
    state
  end

  ## GenServer callbacks

  def init([registry, definitions]) do
    initialize_state_table(registry)
    Enum.each(definitions, fn definition -> initialize_metric(registry, definition) end)
    state = %{registry: registry, definitions: definitions}
    {:ok, state}
  end

  def handle_call(:get_metric_names, _from, state) do
    metric_names = Enum.map(state.definitions, & &1.metric_name)
    {:reply, metric_names, state}
  end

  def handle_call({:collect, metric_name}, _from, state) do
    reply =
      case Enum.find(state.definitions, &(&1.metric_name == metric_name)) do
        nil ->
          {:error, :not_found}

        # TODO: Definition and state probably should be both kept in ETS.
        definition ->
          metric_state = get_metric_state(state.registry, metric_name)
          measurements = definition.callback_module.collect(metric_state)
          {:ok, measurements}
      end

    {:reply, reply, state}
  end

  ## Helpers

  @spec assert_unique_definitions!([Metrics.metric_definition()]) :: :ok | no_return()
  defp assert_unique_definitions!(definitions) do
    definitions
    |> Enum.group_by(& &1.metric_name, fn _ -> 1 end)
    |> Enum.map(fn {metric_name, list} -> {metric_name, length(list)} end)
    |> Enum.find(fn {_metric_name, occurences} -> occurences != 1 end)
    |> case do
      {metric_name, _occurences} ->
        raise ArgumentError, "Metric #{inspect(metric_name)} is not unique"

      nil ->
        :ok
    end
  end

  @spec initialize_state_table(registry) :: :ok
  defp initialize_state_table(registry) do
    :ets.new(state_table_name(registry), [
      :set,
      :public,
      :named_table,
      keypos: 1,
      write_concurrency: true,
      read_concurrency: true
    ])
  end

  @spec state_table_name(registry) :: :ets.tab()
  defp state_table_name(registry), do: registry

  @spec initialize_metric(registry, Metrics.metric_definition()) :: :ok
  defp initialize_metric(registry, definition) do
    # TODO: Handle initialization failure.
    {:ok, metric_state} = definition.callback_module.init(definition.metric_opts)
    set_metric_state(registry, definition.metric_name, metric_state)
    # Process name registration should in most cases guarantee uniqueness of
    # the registry, and metric name is unique in the scope of a single registry,
    # thus {registry, metric_name} tuple should be unique.
    handler_id = {registry, definition.metric_name}

    handler_config = %{
      metric_name: definition.metric_name,
      callback_module: definition.callback_module,
      tags: definition.tags,
      registry: registry
    }

    # TODO: Handle duplicate handler ID (rare, but might happen).
    # Alternatively, make the IDs truly unique (but this would make them
    # non-deterministic and undiscoverable)>
    :ok =
      Telemetry.attach(
        handler_id,
        definition.event_name,
        Metrics.UpdateEventHandler,
        :handle_event,
        handler_config
      )
  end
end
