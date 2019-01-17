# Telemetry.Metrics

[![CircleCI](https://circleci.com/gh/beam-telemetry/telemetry_metrics.svg?style=svg)](https://circleci.com/gh/beam-telemetry/telemetry_metrics)
[![Codecov](https://codecov.io/gh/beam-telemetry/telemetry_metrics/branch/master/graphs/badge.svg)](https://codecov.io/gh/beam-telemetry/telemetry_metrics/branch/master/graphs/badge.svg)

Defines data model and specifications for aggregating Telemetry events.

Telemetry.Metrics provides functions for building *metric specifications* - structs describing how
values of particular events should be aggregated. Metric specifications can be provided to a reporter
which knows how to translate the events into a metric *in the system it reports to*. This is the crucial
part of this library design - it doesn't aggregate events itself in any way, it relies on 3rd party
reporters to perform this work in a way that makes the most sense for a metrics system at hand.

To give a more concrete example, let's say that you want to count the number of database queries your
application makes, and you want a separate counter for each query type and table. In this case, you
would construct the following metric specification:

```elixir
Telemetry.Metrics.counter(
  "db.query",
  name: "db.query.count",
  tags: [:table, :query_type]
)
```

This specification means that:

* metric should count the number of times a `[:db, :query]` event has been emitted, regardless of
  event value
* the name of the metric is `[:db, :query, :count]`
* the count should be broken down by each unique `:table`/`:query_type` pair found in event metadata

Now when we provide such specification to the reporter and emit following events

```elixir
:telemetry.execute([:db, :query], 32, %{table: "users", query_type: "select"})
:telemetry.execute([:db, :query], 67, %{table: "users", query_type: "insert"})
:telemetry.execute([:db, :query], 18, %{table: "users", query_type: "select"})
:telemetry.execute([:db, :query], 15, %{table: "users", query_type: "select"})
```

we expect to find the following aggregations in the metric system we report to

| table      | query_type | count |
|------------|------------|-------|
| `users`    | `select`   | 1     |
| `users`    | `create`   | 1     |
| `products` | `select`   | 2     |

The way in which reporters aggregate or export this data is not in the scope of this project. Rather,
a goal is to define a standardized set of aggregations that will be supported by reporters.

## Copyright and License

Telemetry.Metrics is copyright (c) 2018 Chris McCord and Erlang Solutions.

Telemetry.Metrics source code is released under Apache License, Version 2.0.

See [LICENSE](LICENSE) and [NOTICE](NOTICE) files for more information.