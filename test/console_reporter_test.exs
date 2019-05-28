defmodule Telemetry.Metrics.ConsoleReporterTest do
  use ExUnit.Case, async: true

  import Telemetry.Metrics
  import ExUnit.CaptureLog

  setup do
    metrics = [
      last_value("vm.memory.binary", unit: :byte),
      counter("vm.memory.total"),
      summary("http.request.response_time",
        tag_values: fn %{foo: :bar} -> %{bar: :baz} end,
        tags: [:bar]
      )
    ]

    {:ok, device} = StringIO.open("")
    opts = [metrics: metrics, device: device]
    formatter = start_supervised!({Telemetry.Metrics.ConsoleReporter, opts})
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
           And tag values: %{}

           Metric measurement: :total (counter)
           With value: 200
           And tag values: %{}

           """
  end

  test "prints missing and bad measurements", %{device: device} do
    :telemetry.execute([:vm, :memory], %{total: :hundred}, %{foo: :bar})
    {_in, out} = StringIO.contents(device)

    assert out == """
           [Telemetry.Metrics.ConsoleReporter] Got new event!
           Event name: vm.memory
           All measurements: %{total: :hundred}
           All metadata: %{foo: :bar}

           Metric measurement: :binary (last_value)
           No value available (metric skipped)

           Metric measurement: :total (counter)
           With value: :hundred (WARNING! measurement should be a number)
           And tag values: %{}

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
           And tag values: %{bar: :baz}

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
           Errored when processing! (metric skipped)

           """
  end
end
