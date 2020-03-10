# Writing Reporters

Reporters are a crucial part of Telemetry.Metrics ecosystem. Without them, metric
definitions are merely... definitions. This guide aims to help in writing reporters
in a proper way.

> Before writing the reporter for your favourite monitoring system, make sure that one isn't
> already available on Hex.pm - it might make sense to contribute and improve the existing
> solution than starting from scratch.

Let's get started!

## Specification

  - Reporters MUST accept a list of metric definitions as input when being started
  - Reporters MUST attach handlers to events contained in these definitions
  - Reporters MUST extract the measurement and selected tags specified by the metric definitions
  - Reporters SHOULD handle events in a way that makes sense for whatever it
    is publishing to
  - Reporters MUST clean up on exit by detaching all event handlers they have created
  - Reporters MUST honor `keep` recording rule functions
  - Reporters MUST skip events with missing or invalid measurements or tags

### Accepting Metric Definitions as Input

This one is quite easy - you need to give your users a way to actually tell you what metrics
they want to track. It's essential to give users an option to provide metric definitions
at runtime (e.g. when their application starts). For example, let's say you're building a
`PigeonReporter`.

If the reporter was process-based, you could provide a `start_link/1` function that accepts
a list of metric definitions:

```elixir
metrics = [
  counter("..."),
  last_value("..."),
  summary("...")
]

PigeonReporter.start_link(metrics: metrics)
```

If the reporter doesn't support metrics of particular type, it may either:

  1. Log a warning and discard the metric
  2. Log a warning and convert the metric to an equivalent type. For example, a reporter
     may convert an histogram into a summary or simpler metric in case it is not supported

We recommend all reporters to include a summary table of which metrics are supported and
their equivalents on the adapter terminology.

Reporter-specific options for individual metrics may be passed on the `:reporter_options`
key of the metric definitions. These options can be used to define options such as sample
rates, percentiles, rates, etc. Reporters should validate any options they accept and
provide useful exception messages.

### Attaching event handlers

Event handlers are attached using `:telemetry.attach/4` function. To reduce overhead of
installing many event handlers, you can install a single handler for multiple metrics
based on the same event but note that any exception will cause all metrics on under that
handler. You can achieve this by grouping the metrics by event name:

```elixir
Enum.group_by(metrics, & &1.event_name)
```

Note that handler IDs need to be unique - you can generate completely random blobs of
data, or use something that you know needs to be unique anyway, e.g. some combination
of reporter name, event name, and something which is different for multiple instances
of the same reporter (PID is a good choice as most reporters should be backed by a process):

```elixir
id = {PigeonReporter, metric.event_name, self()}
```

Putting it all together:

```elixir
for {event, metrics} <- Enum.group_by(metrics, & &1.event_name) do
  id = {__MODULE__, event, self()}
  :telemetry.attach(id, event, &handle_event/4, metrics)
end
```

### Reacting to events

When consuming events, there are five steps to take into account:

1. If a `keep` recording rule function has been provided, the reporter MUST record the metric
   only if the function returns `true`.

2. Extract event measurements from the event. Measurements are optional, so we must skip
   reporting that particular measurement if it is not available;

3. Extract all the relevant tags from the event metadata (if they are supported by the reporter);

4. Implement the logic specific to the reporter;

5. How to react to errors. One option is to let the `handle_event/4` callback fail, but
that means we will no longer listen to any future event. Another option is to rescue any
error and log them. That's the approach we will take in this example. However, be careful!
If an event always contains bad data, then we will log an error every time it is emitted;

Let's see a simple handler implementation that takes all of those four items into account:

```elixir
def handle_event(_event_name, measurements, metadata, metrics) do
  for metric <- metrics do
    try do
      measurement = extract_measurement(metric, measurements)
      tags = extract_tags(metric, metadata)

      if keep?(metric, metadata) do

        # record and send
      end
    rescue
      e ->
        Logger.error("Could not format metric #{inspect metric}")
        Logger.error(Exception.format(:error, e, __STACKTRACE__))
    end
  end
end
```

The implementation of `keep?/2` might look like:

```elixir
defp keep?(%{keep: nil}, _metadata), do: true
defp keep?(metric, metadata), do: metric.filter.(metadata)
```

The implementation of `extract_measurement/2` might look as follows:

```elixir
def extract_measurement(metric, measurements) do
  case metric.measurement do
    fun when is_function(fun, 1) -> fun.(measurements)
    key -> measurements[key]
  end
end
```

Since `:measurement` in the metric definition can be both an arbitrary term (to be used
as key to fetch the measurement) or a function, we need to handle both cases.

> Note: Telemetry.Metrics can't guarantee that the extracted measurement's value is a number.
> Each reporter can handle this scenario properly, either by logging a warning, detaching
> the handler etc.

We also need to implement the `extract_tags/2` function:

```elixir
def extract_tags(metric, metadata) do
  tag_values = metric.tag_values.(metadata)
  Map.take(tag_values, metric.tags)
end
```

First we need to apply last-minute transformation to the metadata using the `:tag_values`
function, then we fetch all transformed metadata, ignoring any tag that may not be available.

### Detaching Handlers on Termination

To leave the system in a clean state, the reporter must detach the event handlers it installed
when it's being stopped or terminated unexpectedely. This can be done by trapping exits in the
`init` function and implementing the terminate callback, or having a dedicated process
responsible only for the cleanup (e.g. by using monitors).

## Documentation

It's extremely important that reporters document how `Telemetry.Metrics` metric types, names,
and tags are translated to metric types and identifiers in the system they publish metrics to
(this is particularly important for a summary metric which is broadly defined). They should also
document if some metric types are not supported at all.

## Examples

This repository ships with a `Telemetry.Metrics.ConsoleReporter` that prints data to the
terminal as an example. Official reporters can be found in the [BEAM Telemetry Github Organization](https://github.com/beam-telemetry). You may search for other reporters on hex.pm.

