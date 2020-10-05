defmodule Telemetry.Metrics.ConsoleReporterTest do
  use ExUnit.Case, async: true

  import Telemetry.Metrics
  import ExUnit.CaptureLog

  def metadata_measurement(_measurements, metadata) do
    map_size(metadata)
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
      )
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
           All metadata: %{boom: :pow, foo: :bar}

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

           Metric measurement: &Telemetry.Metrics.ConsoleReporterTest.metadata_measurement/2 (sum)
           With value: 1
           Tag values: %{}

           """
  end
end
