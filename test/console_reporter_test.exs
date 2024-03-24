defmodule Telemetry.Metrics.ConsoleReporterTest do
  use ExUnit.Case, async: true

  import Telemetry.Metrics
  import ExUnit.CaptureLog

  def metadata_measurement(_measurements, metadata) do
    map_size(metadata)
  end

  def measurement(%{duration: duration} = _measurement) do
    duration
  end

  setup do
    metrics = [
      last_value("vm.memory.binary", unit: :byte),
      counter("vm.memory.total"),
      summary("http.request.response_time",
        tag_values: fn
          %{foo: :bar} -> %{bar: :baz}
        end,
        tags: [:bar],
        drop: fn metadata ->
          metadata[:boom] == :pow
        end
      ),
      sum("telemetry.event_size.metadata",
        measurement: &__MODULE__.metadata_measurement/2
      ),
      distribution("phoenix.endpoint.stop.duration",
        measurement: &__MODULE__.measurement/1
      ),
      summary("my_app.repo.query.query_time", unit: {:native, :millisecond})
    ]

    {:ok, device} = StringIO.open("")
    opts = [metrics: metrics, device: device]
    {:ok, formatter} = Telemetry.Metrics.ConsoleReporter.start_link(opts)
    {:ok, formatter: formatter, device: device}
  end

  test "can be a named process" do
    {:ok, pid} = Telemetry.Metrics.ConsoleReporter.start_link(metrics: [], name: __MODULE__)
    assert Process.whereis(__MODULE__) == pid
  end

  test "raises when missing :metrics option" do
    msg = "the :metrics option is required by Telemetry.Metrics.ConsoleReporter"

    assert_raise ArgumentError, msg, fn ->
      Telemetry.Metrics.ConsoleReporter.start_link(name: __MODULE__)
    end
  end

  test "prints metrics per event", %{device: device} do
    :telemetry.execute([:vm, :memory], %{binary: 100, total: 200}, %{})
    {_in, out} = StringIO.contents(device)

    assert out == """
           [Telemetry.Metrics.ConsoleReporter] Got new event!
           Event name: vm.memory
           All measurements: %{binary: 100, total: 200}
           All metadata: %{}

           Metric measurement: :binary (last_value)
           With value: 100 byte
           Tag values: %{}

           Metric measurement: :total (counter)
           Tag values: %{}

           """
  end

  test "prints missing and bad measurements", %{device: device} do
    :telemetry.execute([:vm, :memory], %{binary: :hundred}, %{foo: :bar})
    {_in, out} = StringIO.contents(device)

    assert out == """
           [Telemetry.Metrics.ConsoleReporter] Got new event!
           Event name: vm.memory
           All measurements: %{binary: :hundred}
           All metadata: %{foo: :bar}

           Metric measurement: :binary (last_value)
           With value: :hundred byte (WARNING! measurement should be a number)
           Tag values: %{}

           Metric measurement: :total (counter)
           Measurement value missing (metric skipped)

           """
  end

  test "prints tag values measurements", %{device: device} do
    :telemetry.execute([:http, :request], %{response_time: 1000}, %{foo: :bar})
    {_in, out} = StringIO.contents(device)

    assert out == """
           [Telemetry.Metrics.ConsoleReporter] Got new event!
           Event name: http.request
           All measurements: %{response_time: 1000}
           All metadata: %{foo: :bar}

           Metric measurement: :response_time (summary)
           With value: 1000
           Tag values: %{bar: :baz}

           """
  end

  test "filters events", %{device: device} do
    :telemetry.execute([:http, :request], %{response_time: 1000}, %{foo: :bar, boom: :pow})
    {_in, out} = StringIO.contents(device)

    assert out == """
           [Telemetry.Metrics.ConsoleReporter] Got new event!
           Event name: http.request
           All measurements: %{response_time: 1000}
           All metadata: #{inspect(%{boom: :pow, foo: :bar})}

           Metric measurement: :response_time (summary)
           Event dropped

           """
  end

  test "logs bad metrics", %{device: device} do
    log =
      capture_log(fn ->
        :telemetry.execute([:http, :request], %{response_time: 1000}, %{bar: :baz})
      end)

    assert log =~ "Could not format metric %Telemetry.Metrics.Summary"
    assert log =~ "** (FunctionClauseError) no function clause matching"

    {_in, out} = StringIO.contents(device)

    assert out == """
           [Telemetry.Metrics.ConsoleReporter] Got new event!
           Event name: http.request
           All measurements: %{response_time: 1000}
           All metadata: %{bar: :baz}

           Metric measurement: :response_time (summary)
           Errored when processing (metric skipped - handler may detach!)

           """
  end

  test "can use metadata in the event measurement calculation", %{device: device} do
    :telemetry.execute([:telemetry, :event_size], %{}, %{key: :value})
    {_in, out} = StringIO.contents(device)

    assert out == """
           [Telemetry.Metrics.ConsoleReporter] Got new event!
           Event name: telemetry.event_size
           All measurements: %{}
           All metadata: %{key: :value}

           Metric measurement: :metadata [via &Telemetry.Metrics.ConsoleReporterTest.metadata_measurement/2] (sum)
           With value: 1
           Tag values: %{}

           """
  end

  test "can use measurement map in the event measurement calculation", %{device: device} do
    :telemetry.execute([:phoenix, :endpoint, :stop], %{duration: 100}, %{})

    {_in, out} = StringIO.contents(device)

    assert out == """
           [Telemetry.Metrics.ConsoleReporter] Got new event!
           Event name: phoenix.endpoint.stop
           All measurements: %{duration: 100}
           All metadata: %{}

           Metric measurement: :duration [via &Telemetry.Metrics.ConsoleReporterTest.measurement/1] (distribution)
           With value: 100
           Tag values: %{}

           """
  end

  test "can show metric name and unit conversion fun", %{device: device, formatter: formatter} do
    event = [:my_app, :repo, :query]
    native_time = :erlang.system_time()

    expected_millisecond = native_time * (1 / System.convert_time_unit(1, :millisecond, :native))

    expected_measurement_fun = measurement_fun(event, :query_time, formatter, device)

    :telemetry.execute(event, %{query_time: native_time})

    {_in, out} = StringIO.contents(device)

    assert out == """
           [Telemetry.Metrics.ConsoleReporter] Got new event!
           Event name: my_app.repo.query
           All measurements: %{query_time: #{native_time}}
           All metadata: %{}

           Metric measurement: :query_time [via #{inspect(expected_measurement_fun)}] (summary)
           With value: #{expected_millisecond} millisecond
           Tag values: %{}

           """
  end

  defp measurement_fun(event, measurement, formatter, device) do
    name = event ++ [measurement]

    event
    |> :telemetry.list_handlers()
    |> Enum.find_value(fn
      %{id: {Telemetry.Metrics.ConsoleReporter, ^event, ^formatter}, config: {config, ^device}} ->
        Enum.find_value(config, fn %{name: ^name, measurement: fun} when is_function(fun) ->
          fun
        end)
    end)
  end
end
