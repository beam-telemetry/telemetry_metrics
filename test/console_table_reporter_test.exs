defmodule Telemetry.Metrics.ConsoleTableReporterTest do
  use ExUnit.Case

  import Telemetry.Metrics
  import ExUnit.CaptureLog

  setup do
    metrics = [
      last_value("vm.memory.binary", unit: :byte),
      counter("my_long_application_name_that_is_too_long.vm.memory.total"),
      counter("vm.memory.total"),
      summary("http.request.response_time",
        tag_values: fn
          %{foo: :bar} -> %{bar: :baz}
        end,
        tags: [:bar],
        drop: fn metadata ->
          metadata[:boom] == :pow
        end
      )
    ]

    {:ok, device} = StringIO.open("")
    opts = [metrics: metrics, device: device]
    {:ok, formatter} = Telemetry.Metrics.ConsoleTableReporter.start_link(opts)
    {:ok, formatter: formatter, device: device}
  end

  test "can be a named process" do
    {:ok, pid} = Telemetry.Metrics.ConsoleTableReporter.start_link(metrics: [], name: __MODULE__)
    assert Process.whereis(__MODULE__) == pid
  end

  test "prints metrics per event", %{device: device} do
    :telemetry.execute([:vm, :memory], %{binary: 100, total: 200}, %{})
    {_in, out} = StringIO.contents(device)

    assert out == """
           +--------------------------------------------+
           |                 vm.memory                  |
           +-------------+------------+----------+------+
           | Measurement | Type       | Value    | Tags |
           +-------------+------------+----------+------+
           | binary      | last_value | 100 byte | %{}  |
           | total       | counter    | 200      | %{}  |
           +-------------+------------+----------+------+

           """
  end

  test "prints missing and bad measurements", %{device: device} do
    :telemetry.execute([:vm, :memory], %{binary: :hundred}, %{foo: :bar})
    {_in, out} = StringIO.contents(device)

    assert out == """
           +-------------------------------------------------+
           |                    vm.memory                    |
           +-------------+------------+---------------+------+
           | Measurement | Type       | Value         | Tags |
           +-------------+------------+---------------+------+
           | binary      | last_value | :hundred byte | %{}  |
           | total       | counter    | nil           | nil  |
           +-------------+------------+---------------+------+

           """
  end

  test "prints tag values measurements", %{device: device} do
    :telemetry.execute([:http, :request], %{response_time: 1000}, %{foo: :bar})
    {_in, out} = StringIO.contents(device)

    assert out == """
           +------------------------------------------------+
           |                  http.request                  |
           +---------------+---------+-------+--------------+
           | Measurement   | Type    | Value | Tags         |
           +---------------+---------+-------+--------------+
           | response_time | summary | 1000  | %{bar: :baz} |
           +---------------+---------+-------+--------------+

           """
  end

  test "filters events", %{device: device} do
    :telemetry.execute([:http, :request], %{response_time: 1000}, %{foo: :bar, boom: :pow})
    {_in, out} = StringIO.contents(device)

    assert out == """
           +------------------------------------------------+
           |                  http.request                  |
           +---------------+---------+---------------+------+
           | Measurement   | Type    | Value         | Tags |
           +---------------+---------+---------------+------+
           | response_time | summary | event dropped | nil  |
           +---------------+---------+---------------+------+

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
           +-------------------------------------------+
           |               http.request                |
           +---------------+---------+-------+---------+
           | Measurement   | Type    | Value | Tags    |
           +---------------+---------+-------+---------+
           | response_time | summary | error | skipped |
           +---------------+---------+-------+---------+

           """
  end

  test "truncates long titles", %{device: device} do
    :telemetry.execute(
      [:my_long_application_name_that_is_too_long, :vm, :memory],
      %{total: 200},
      %{}
    )

    {_in, out} = StringIO.contents(device)

    assert out == """
           +--------------------------------------+
           | my_long_application_name_that_is_... |
           +-------------+---------+-------+------+
           | Measurement | Type    | Value | Tags |
           +-------------+---------+-------+------+
           | total       | counter | 200   | %{}  |
           +-------------+---------+-------+------+

           """
  end
end
