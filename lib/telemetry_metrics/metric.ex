defmodule Telemetry.Metrics.Metric do
  @moduledoc """
  A behaviour for various metric types.
  """

  @type state :: term()

  ## Callbacks

  @doc """
  Initializes the state of the metric.
  """
  ## TODO: Allow to return a PID here so that metrics can be supervised.
  @callback init(options :: term()) :: {:ok, state()} | {:error, reason :: term()}

  @doc """
  Updates measurement identified by the given tagset.
  """
  # NOTE: Maybe we should pass whole event metadata to metric?
  # NOTE: Should we expect the metric to return the state here? Some metrics'
  # state might not change on update - especially if they're backed by the process..
  @callback update(Telemetry.event_value(), Telemetry.Metrics.tagset(), state()) :: state()

  @doc """
  Returns all measurements produced by the metric.

  The set of datapoints belonging to single measurement should not be empty.
  """
  @callback collect(state) :: [Telemetry.Metrics.measurement()]
end
