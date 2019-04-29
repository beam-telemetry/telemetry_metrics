# Overview

Telemetry.Metrics provides a common interface for defining metrics based on
[`:telemetry`](https://github.com/beam-telemetry/telemetry) events. While a single event means that
_a thing_ happened (e.g. an HTTP request was sent or a DB query returned a result), a metric
is an aggregation of those events over time. For instance, we could count the number of HTTP
requests, or keep track of the sum of payload sizes returned by DB queries.

To give a more concrete example, imagine that somewhere in your code you have a function which sends
an HTTP request, measures the time it took to get a response, and emits an event with the information:

```elixir
:telemetry.execute([:http, :request, :done], %{duration: duration})
```

You could define a counter metric, which counts how many HTTP requests were completed:

```elixir
Telemetry.Metrics.counter("http.request.done.count")
```

or you could use a distribution metric to see how many queries were completed in particular time
buckets:

```elixir
Telemetry.Metrics.distribution("http.request.done.duration", buckets: [100, 200, 300])
```

> There are a couple more metric types, and they are all described in detail in the "Metric types"
> section.

Because of the fact that metrics are based only on events being emitted, you can easily create
metrics from events published by the libraries you're using in your project. But metric definitions
on their own are not enough - aggregated metrics need to be sent somewhere, so that you can inspect
how your system behaves - and that's what reporters are for.

## Reporters

Reporters are responsible for publishing metrics to some system where they can be inspected. For
example, there could be a reporter pushing metrics to StatsD, some time-series database, or exposing
a HTTP endpoint for Prometheus to scrape.

Under the hood, reporter needs to attach event handlers to relevant events and extract specific
measurement. This information is included in the metric definitions.

Note that Telemetry.Metrics package doesn't provide any reporter itself.

## Metric definitions

[`counter/2`](./Telemetry.Metrics.html#counter/2), [`sum/2`](./Telemetry.Metrics.html#sum/2),
[`last_value/2`](./Telemetry.Metrics.html#last_value/2),
[`summary/2`](./Telemetry.Metrics.html#summary/2) and
[`distribution/2`](./Telemetry.Metrics.html#distribution/2) functions all return metric defintions.

The most basic metric definition looks like this

```elixir
sum("http.request.payload_size")
```

The first argument to the metric definition function is a metric name - this is what the reporter
will use to identify this metric when publishing it. The metric name also determines what event and
measurement should be used to produce metric values:

```
 [:http , :request]    :payload_size
 <-- event name --> <-- measurement -->
```

that is, by default, all but last segments of the metric name determine the event name, and the last
segment determines the measurement.

If you wish to use a different event name or measurement, they can be overriden using `:event_name`
and `:measurement` options respectively (you can read more about them in the "Shared options"
section in the docs for [`Telemetry.Metrics`](./Telemetry.Metrics.html#shared-options) module)

## Metric types

Telemetry.Metrics defines four basic metric types:

- a counter simply counts the number of emitted events, regardless of measurements included in the
  events. Since the measurement does not matter in case of a counter, we recommend using `count`
  as a measurement, e.g. `"http.request.count"`
- a `last_value` metric holds the value of a selected measurement found in the most recent event
- a sum adds up the values of a selected measurement in all the events
- a summary aggregates measurement values into a set of statistics, e.g. minimum and maximum, mean,
  or percentiles. The exact set of available statistics depends on the reporter in use
- a distribution keeps track of the histogram of the selected measurement, i.e. how many
  measurements fall into defined buckets. Histogram allows to compute useful statistics about
  the data, like percentiles, minimum, or maximum.

  For example, given boundaries `[0, 100, 200]`, the distribution metric produces four values:

  - number of measurements less than or equal to 0
  - number of measurements greater than 0 and less than or equal to 100
  - number of measurements greater than 100 and less than or equal to 200
  - number of measurements greater than 200

If the monitoring solution doesn't provide metric types exactly as defined above but supports
metrics resembling them, the reporter should properly document the differences between the expected
and actual behaviour.

It's also possible that a reporter library provides its own, specialized function for building
metric definitions for metric types specific to the system it publishes metrics to.

## Breaking down metric values by tags

Sometimes it's not enough to have a global overview of all HTTP requests received or all DB queries
made. It's often more helpful to break down this data, for example, we might want to have separate
metric values for each unique database table and operation name (`select`, `insert` etc.) to see
how these particular queries behave.

This is where tagging comes into play. All metric definitions accept a `:tags` option:

```elixir
count("db.query.count", tags: [:table, :operation])
```

The above definition means that we want to keep track of the number of queries, but we want
a separate counter for each unique pair of table and operation. Tag values are fetched from event
metadata - this means that in this example, `[:db, :query]` events need to include `:table` and
`:operation` keys in their payload:

```elixir
:telemetry.execute([:db, :query], %{duration: 198}, %{table: "users", operation: "insert"})
:telemetry.execute([:db, :query], %{duration: 112}, %{table: "users", operation: "select"})
:telemetry.execute([:db, :query], %{duration: 201}, %{table: "sessions", operation: "insert"})
:telemetry.execute([:db, :query], %{duration: 212}, %{table: "sessions", operation: "insert"})
```

The result of aggregating the events above looks like this:

| table    | operation | count |
| -------- | --------- | ----- |
| users    | insert    | 1     |
| users    | select    | 1     |
| sessions | insert    | 2     |

The approach where we create a separate metric for some unique set of properties is called
a multi-dimensional data model.

### Transforming event metadata for tagging

Finally, sometimes there is a need to modify event metadata before it's used for tagging. Each
metric definition accepts a function in `:tag_values` option which transforms the metadata into
desired shape. Note that this function is called for each event, so it's important to keep it fast
if the rate of events is high.

## Converting units

It might happen that the unit of measurement we're tracking is not the desirable unit for the
metric values, e.g. events are emitted by a 3rd-party library we do not control, or a reporter
we're using requires specific unit of measurement.

For these scenarios, each metric definition accepts a `:unit` option in a form of a tuple:

```elixir
summary("http.request.duration", unit: {from_unit, to_unit})
```

This means that the measurement will be converted from `from_unit` to `to_unit` before being used
for updating the metric. Currently, only time conversions are supported, which means that both
`from_unit` and `to_unit` need to be one of `:second`, `:millisecond`, `:microsecond`,
`:nanosecond`, or `:native`.

For example, to convert HTTP request duration from `:native` time unit to milliseconds you'd write:

```elixir
summary("http.request.duration", unit: {:native, :millisecond})
```

## VM metrics

Telemetry.Metrics doesn't have a special treatment for the VM metrics - they need to be based on
the events like all other metrics.

`Telemetry.Poller` package exposes a bunch of VM-related metrics via `:telemetry` events.
For example, when you add it to your dependencies, you can create a metric keeping track of total
allocated VM memory:

    last_value("vm.memory.total")

The last value metric is usually the best fit for VM metrics exposed by the Poller, as the events are
emitted periodically and we're only interested in the most recent measurement.

You can read more about available events and measurements in the `Telemetry.Poller` documentation.
