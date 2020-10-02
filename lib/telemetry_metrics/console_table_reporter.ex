defmodule Telemetry.Metrics.ConsoleTableReporter do
  @moduledoc """
  A reporter that prints events and metrics to the terminal in a table.

  This is useful for debugging and discovering all available
  measurements and metadata in an event.

  For example, imagine the given metrics:

      metrics = [
        last_value("vm.memory.binary", unit: :byte),
        counter("vm.memory.total")
      ]

  A console table reporter can be started as a child of your your supervision
  tree as:

      {Telemetry.Metrics.ConsoleTableReporter, metrics: metrics}

  Now when the "vm.memory" telemetry event is dispatched, we will see
  reports like this:

      +--------------------------------------------+
      |                 vm.memory                  |
      +-------------+------------+----------+------+
      | Measurement | Type       | Value    | Tags |
      +-------------+------------+----------+------+
      | binary      | last_value | 100 byte | %{}  |
      | total       | counter    | 200      | %{}  |
      +-------------+------------+----------+------+

  """

  use GenServer
  require Logger

  def start_link(opts) do
    server_opts = Keyword.take(opts, [:name])
    device = opts[:device] || :stdio

    metrics =
      opts[:metrics] ||
        raise ArgumentError, "the :metrics option is required by #{inspect(__MODULE__)}"

    GenServer.start_link(__MODULE__, {metrics, device}, server_opts)
  end

  @impl true
  def init({metrics, device}) do
    Process.flag(:trap_exit, true)
    groups = Enum.group_by(metrics, & &1.event_name)

    for {event, metrics} <- groups do
      id = {__MODULE__, event, self()}
      :telemetry.attach(id, event, &handle_event/4, {metrics, device})
    end

    {:ok, Map.keys(groups)}
  end

  @impl true
  def terminate(_, events) do
    for event <- events do
      :telemetry.detach({__MODULE__, event, self()})
    end

    :ok
  end

  defp handle_event(event_name, measurements, metadata, {metrics, device}) do
    title = Enum.join(event_name, ".")

    rows =
      for %struct{} = metric <- metrics do
        name = Enum.join(metric.name, ".") |> String.trim_leading("#{title}.")
        type = to_string(metric(struct))

        values =
          try do
            measurement = extract_measurement(metric, measurements)
            tags = extract_tags(metric, metadata)

            cond do
              is_nil(measurement) ->
                ["nil", "nil"]

              not keep?(metric, metadata) ->
                ["event dropped", "nil"]

              metric.__struct__ == Telemetry.Metrics.Counter ->
                ["#{inspect(measurement)}", "#{inspect(tags)}"]

              true ->
                # TODO log warning when not a number
                [
                  "#{inspect(measurement)}#{unit(metric.unit)}",
                  "#{inspect(tags)}"
                ]
            end
          rescue
            e ->
              Logger.error([
                "Could not format metric #{inspect(metric)}\n",
                Exception.format(:error, e, System.stacktrace())
              ])

              ["error", "skipped"]
          end

        [name, type] ++ values
      end

    table = render_table(rows, ["Measurement", "Type", "Value", "Tags"], title)
    IO.puts table
    IO.puts(device, table)
  end

  defp keep?(%{keep: nil}, _metadata), do: true
  defp keep?(metric, metadata), do: metric.keep.(metadata)

  defp extract_measurement(metric, measurements) do
    case metric.measurement do
      fun when is_function(fun, 1) -> fun.(measurements)
      key -> measurements[key]
    end
  end

  defp unit(:unit), do: ""
  defp unit(unit), do: " #{unit}"

  defp metric(Telemetry.Metrics.Counter), do: "counter"
  defp metric(Telemetry.Metrics.Distribution), do: "distribution"
  defp metric(Telemetry.Metrics.LastValue), do: "last_value"
  defp metric(Telemetry.Metrics.Sum), do: "sum"
  defp metric(Telemetry.Metrics.Summary), do: "summary"

  defp extract_tags(metric, metadata) do
    tag_values = metric.tag_values.(metadata)
    Map.take(tag_values, metric.tags)
  end

  defp render_table(rows, header, title) do
    all_rows = [header] ++ rows
    transposed = transpose(all_rows)

    lengths =
      Enum.map(transposed, fn row ->
        Enum.map(row, &String.length("#{&1}")) |> Enum.max()
      end)

    blank_cells = List.duplicate("", length(header))

    render_title(title, lengths) ++
      line(blank_cells, lengths) ++
      render_row(header, lengths) ++
      line(blank_cells, lengths) ++
      [Enum.map(rows, &render_row(&1, lengths))] ++
      line(blank_cells, lengths)
  end

  defp render_title(title, lengths) do
    # (row_len * 3) considers 2 pad characters and a separator character
    title_len = Enum.sum(lengths) + length(lengths) * 3 - 1
    padding = title_len - String.length(title)

    {left_pad, title, right_pad} =
      if padding < 0 do
        {1, String.slice(title, 0..(title_len - 6)) <> "...", 1}
      else
        left_pad = div(padding, 2)
        right_pad = left_pad + rem(padding, 2)
        {left_pad, title, right_pad}
      end

    [
      "+#{String.duplicate("-", title_len)}+\n",
      "|#{String.duplicate(" ", left_pad)}#{title}#{String.duplicate(" ", right_pad)}|\n"
    ]
  end

  defp line(row, lengths) do
    render_row(row, lengths, pad: "-", separator: "+")
  end

  defp render_row(row, lengths, opts \\ []) do
    pad = Keyword.get(opts, :pad, " ")
    separator = Keyword.get(opts, :separator, "|")

    [
      Enum.zip(lengths, row)
      |> Enum.map(fn {len, cell} ->
        cell = to_string(cell)
        padding = len - String.length(cell) + 1
        "#{separator}#{pad}#{cell}#{String.duplicate(pad, padding)}"
      end)
    ] ++
      ["#{separator}\n"]
  end

  defp transpose([[] | _]), do: []
  defp transpose(x), do: [Enum.map(x, &hd/1) | transpose(Enum.map(x, &tl/1))]
end
