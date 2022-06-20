defmodule Telemetry.Metrics.Emitter do
  @moduledoc """
  Emit metrics declared with `Telemetry.Metrics`.

  Metric names are strings separated by `.`. Each name must have at least two
  segments, the last being the measurement.

  ### Examples

  ```elixir
  Emitter.increment("request.count")
  ```
  """

  @doc """
  Increment the value from the counter metric. The last segment of the metric is
  the key to the measurement, while the value is always 1.

  Define the metric using `TelemetryMetrics.counter/2`.
  """
  @spec increment(
          counter :: String.t(),
          metadata :: %{String.t() => String.t()} | %{atom() => String.t()}
        ) :: :ok
  def increment(counter, metadata \\ %{}) do
    counter
    |> split()
    |> then(fn {metric, measurement} ->
      :telemetry.execute(metric, %{measurement => 1}, metadata)
    end)
  end

  @doc """
  Emit the current value of the gauge as a number.

  Define the metric using `TelemetrMetrics.last_value/2`.
  """
  @spec gauge(
          metric :: String.t(),
          value :: number(),
          metadata :: %{String.t() => String.t()} | %{atom() => String.t()}
        ) :: :ok
  def gauge(metric, value, metadata \\ %{}) do
    metric
    |> split()
    |> then(fn {metric, measurement} ->
      :telemetry.execute(metric, %{measurement => value}, metadata)
    end)
  end

  @doc """
  Emit a measurement metric.

  If an integer is given then emit the value using the final segment as the
  measurement of the metric. In this case the return value is `:ok`.

  If a function is given, measure the duration of the execution of the function.

  In this latter case, the metric name must match in `prefix.stop.duration`
   where `prefix` is any aribitrary metric name and the suffix `.stop.duration`
  is required. The metric is reported as `prefix.stop` with a measurement of
  `:duration`.

  The result of `function.()` is returned.

  Define the metric using `TelemetryMetrics.summary/2`.

  ## Examples

  Declaring the metric using `TelemetryMetrics.summary/2`:

  ```elixir
  TelemetryMetrics.summary("my.external.service.call.stop.duration", tags: [:operation])
  ```

  Emitting the metirc using `TelemetryMetrics.Emitter.measure/3`:

  ```elixir
  TelemetryMetrics.Emitter.measure("my.external.service.call.stop.duration", fn ->
    MyExternalService.call(...)
  end, %{operation: :record})

  The metric will be `my.external.service.stop` with a measurement of
  `duration: n` where `n` is the duration of the given function call.

  Or when giving the measurement value itself:

  ```elixir
  TelemetryMetrics.summary("my.external.service.call.time", tags: [:operation])
  ```

  Emitting the metirc using `TelemetryMetrics.Emitter.measure/3`:

  ```elixir
  TelemetryMetrics.Emitter.measure("my.external.service.call.time", 100, %{operation: :record})
  ```

  The metric will be `my.external.service.call` with a measurement of `time:
  100`.
  """
  @spec measure(
          metric :: String.t(),
          function_or_duration :: function() | integer(),
          metadata :: %{String.t() => String.t()} | %{atom() => String.t()}
        ) :: any()

  def measure(metric, function_or_integer, metadata \\ %{})

  def measure(metric, function, stop_metadata) when is_function(function) do
    metric
    |> stop_duration_split()
    |> then(fn {prefix, [:stop, :duration]} ->
      :telemetry.span(prefix, %{}, fn ->
        {function.(), stop_metadata}
      end)
    end)
  end

  def measure(metric, duration, metadata) do
    metric
    |> split()
    |> then(fn {metric, measurement} ->
      :telemetry.execute(metric, %{measurement => duration}, metadata)
    end)
  end

  defp split(metric) do
    String.split(metric, ".")
    |> Enum.map(&String.to_atom/1)
    |> Enum.split(-1)
    |> then(fn
      {[], [_measurement]} ->
        raise """
        Metric names must have at least one segment separating the metric name from the measurement:
        \t`metric_name.measurement` or `metric.name.measurement`, etc.

        \t#{metric} has no segments.
        """

      {metric, [measurement]} ->
        {metric, measurement}
    end)
  end

  defp stop_duration_split(metric) do
    String.split(metric, ".")
    |> Enum.map(&String.to_atom/1)
    |> Enum.split(-2)
    |> then(fn
      {prefix, [:stop, :duration]} ->
        {prefix, [:stop, :duration]}

      metric ->
        raise """
        Metrics given for measuring a function duration must end with ".stop.duration".

        \t#{metric} is invalid.
        """
    end)
  end
end
