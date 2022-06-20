defmodule Telemetry.Metrics.EmitterTest do
  use ExUnit.Case, async: false

  import Telemetry.Metrics
  import ExUnit.CaptureLog

  alias Telemetry.Metrics.Emitter

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
      summary("service.request.stop.duration", tags: [:foo]),
      summary("http.request.response_time",
        tag_values: fn
          %{foo: :bar} -> %{bar: :baz}
        end,
        tags: [:bar],
        drop: fn metadata ->
          metadata[:boom] == :pow
        end
      ),
      sum("telemetry.event.size",
        measurement: &__MODULE__.metadata_measurement/2
      ),
      distribution("phoenix.endpoint.stop.duration",
        measurement: &__MODULE__.measurement/1
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

  test "raises when missing :metrics option" do
    msg = "the :metrics option is required by Telemetry.Metrics.ConsoleReporter"

    assert_raise ArgumentError, msg, fn ->
      Telemetry.Metrics.ConsoleReporter.start_link(name: __MODULE__)
    end
  end

  test "prints metrics per event", %{device: device} do
    Emitter.gauge("vm.memory.binary", 100)
    {_in, out} = StringIO.contents(device)

    assert out == """
           [Telemetry.Metrics.ConsoleReporter] Got new event!
           Event name: vm.memory
           All measurements: %{binary: 100}
           All metadata: %{}

           Metric measurement: :binary (last_value)
           With value: 100 byte
           Tag values: %{}

           Metric measurement: :total (counter)
           Measurement value missing (metric skipped)

           """
  end

  test "prints missing and bad measurements", %{device: device} do
    Emitter.gauge("vm.memory.binary", :hundred, %{foo: :bar})
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
    Emitter.measure("http.request.response_time", 1000, %{foo: :bar})
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

  test "measures function duration", %{device: device} do
    assert :return ==
             Emitter.measure("service.request.stop.duration", fn -> :return end, %{foo: :bar})

    {_in, out} = StringIO.contents(device)

    assert out == """
           [Telemetry.Metrics.ConsoleReporter] Got new event!
           Event name: service.request.stop
           All measurements: %{duration: 2000}
           All metadata: %{foo: :bar}

           Metric measurement: :duration (summary)
           With value: 2000
           Tag values: %{foo: :bar}

           """
  end

  test "filters events", %{device: device} do
    Emitter.measure("http.request.response_time", 1000, %{foo: :bar, boom: :pow})
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
        Emitter.measure("http.request.response_time", 1000, %{bar: :baz})
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
    Emitter.measure("telemetry.event.size", 10, %{key: :value})
    {_in, out} = StringIO.contents(device)

    assert out == """
           [Telemetry.Metrics.ConsoleReporter] Got new event!
           Event name: telemetry.event
           All measurements: %{size: 10}
           All metadata: %{key: :value}

           Metric measurement: &Telemetry.Metrics.EmitterTest.metadata_measurement/2 (sum)
           With value: 1
           Tag values: %{}

           """
  end

  test "can use measurement map in the event measurement calculation", %{device: device} do
    Emitter.measure("phoenix.endpoint.stop.duration", 100)
    {_in, out} = StringIO.contents(device)

    assert out == """
           [Telemetry.Metrics.ConsoleReporter] Got new event!
           Event name: phoenix.endpoint.stop
           All measurements: %{duration: 100}
           All metadata: %{}

           Metric measurement: &Telemetry.Metrics.EmitterTest.measurement/1 (distribution)
           With value: 100
           Tag values: %{}

           """
  end
end
