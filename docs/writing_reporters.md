# Writing reporters

Reporters are a crucial part of Telemetry.Metrics "ecosystem" - without them, metric definitions
are merely.. definitions. This guide aims to help in writing the reporter in a proper way.

> Before writing the reporter for your favourite monitoring system, make sure that one isn't
> already available on Hex.pm - it might make sense to contribute and improve the existing solution
> than starting from scratch.

Let's get started!

## Responsibilites

The reporter has four main responsibilities:

- it needs to accept a list of metric definitions as input when being started
- it needs to attach handlers to events contained in these definitions
- when the events are emitted, it needs to extract the measurement and selected tags, and handle
  them in a way that makes sense for whathever it chooses to publish to
- it needs to detach event handlers when it stops or crashes

### Accepting metric definitions as input

This one is quite easy - you need to give your users a way to actually tell you what metrics they
want to track. It's essential to give users an option to provide metric definitions at runtime
(e.g. when their application starts). For example, let's say you're building a `PigeonReporter`.
If the reporter was process-based, you could provide a `start_link/1` function that accepts a list
of metric definitions:

```elixir
  metrics = [
    counter("..."),
    last_value("..."),
    summary("...")
  ]

  PigeonReporter.start_link(metrics)
```

If the reporter doesn't support metrics of particular type, it should log a warning or return an
error.

### Attaching event handlers

Event handlers are attached using `:telemetry.attach/4` function. To reduce overhead of installing
many event handlers, you can install a single handler for multiple metrics based on the same event.

Note that handler IDs need to be unique - you can generate completely random blobs of data, or use
something that you know needs to be unique anyway, e.g. some combination of reporter name,
event name, and something which is different for multiple instances of the same reporter (PID is a
good choice if the reporter is process-based):

```elixir
id = {PigeonReporter, metric.event_name, self()}
```

Assuming that `metrics` is a list of metric definitions based on `event`, we can attach a handler
like this:

```elixir
:telemetry.attach(id, event, &PigeonReporter.handle_event/4, %{metrics: metrics})
```

### Reacting to events

There are two parts to event handling - the first one is extracting event measurements and tags,
which is the same for all reporters, and the second one is performing logic specific to particular
reporter.

Let's implement the basic event handler attached in the previous section:

```elixir
def handle_event(_event_name, measurements, metadata, %{metrics: metrics}) do
  for metric <- metrics do
    measurement = extract_measurement(metric, measurements)
    tags = extract_tags(metric, metadata)
    # everything else is specific to particular reporter
  end
end
```

As described before, first we extract the measurement and tags, and later perform reporter-specific
logic. The implementation of `extract_measurement/2` might look as follows:

```elixir
def extract_measurement(metric, measurements) do
  case metric.measurement do
    fun when is_function(fun, 1) ->
      fun.(measurements)
    key ->
      measurements[key]
  end
end
```

Since `:measurement` in the metric definition can be both arbitrary term (to be used as key to fetch
the measurement) or a function, we need to handle both cases.

> Note: Telemetry.Metrics can't guarantee that the extracted measurement's value is a number. Each
> reporter can handle this scenario properly, either by logging a warning, detaching the handler etc.

We also need to implement the `extract_tags/2` function:

```elixir
def extract_tags(metric, metadata) do
  tag_values = metric.tag_values.(metadata)
  for tag <- tags, into: %{} do
    case Map.fetch(tag_values, tag) do
      {:ok, value} ->
        Map.put(tags, tag, value)
      :error ->
        Logger.warn("Tag #{inspect(tag)} not found in event metadata: #{inspect(metadata)}")
        Map.put(tags, tag, nil)
    end
  end
end
```

First we need to apply last-minute transformation to the metadata using the `:tag_values` function.
After that, we loop through the list of desired tags and fetch them from transformed metadata - if
the particular key is not present in the metadata, we log a warning and assign `nil` as the tag value.

It is very important that the code executed on every event does not fail, as that would cause
the handler to be permanently removed and prevent the metrics from being updated.

### Detaching the handlers on termination

To leave the system in a clean state, the reporter should detach the event handlers it installed
when it's being stopped or terminated unexpectedely. This can be done by trapping exists and
implementing the terminate callback, or having a dedicated process responsible only for the cleanup
(e.g. by using monitors).

## Documentation

It's extremely important that reporters document how `Telemetry.Metrics` metric types, names,
and tags are translated to metric types and identifiers in the system they publish metrics to
(this is particularly important for a summary metric which is broadly defined). They should also
document if some metric types are not supported at all.

## Examples

To our knowledge, there are not many reporters in the wild yet.
[TelemetryMetricsStatsd](https://github.com/arkgil/telemetry_metrics_statsd) is a reporter which
might serve as an example when implementing your own.
