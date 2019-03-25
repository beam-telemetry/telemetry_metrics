# Telemetry.Metrics

[![CircleCI](https://circleci.com/gh/beam-telemetry/telemetry_metrics.svg?style=svg)](https://circleci.com/gh/beam-telemetry/telemetry_metrics)
[![Codecov](https://codecov.io/gh/beam-telemetry/telemetry_metrics/branch/master/graphs/badge.svg)](https://codecov.io/gh/beam-telemetry/telemetry_metrics/branch/master/graphs/badge.svg)

Telemetry.Metrics provides a common interface for defining metrics based on
[`:telemetry`](https://github.com/beam-telemetry/telemetry) events. While a single event means that
_a thing_ happened (e.g. an HTTP request was sent or a DB query returned a result), a metric
is an aggregation of those events over time.

For example, to build a sum of HTTP request payload size received by your system, you could define
the following metric:

```elixir
Telemetry.Metrics.sum("http.request.payload_size")
```

This definition means that the metric is based on `[:http, :request]` events, and it should sum up
values under `:payload_size` key in events' measurements.

Telemetry.Metrics also supports breaking down the metric values by tags - this means that there
will be a distinct metric for each unique set of selected tags found in event metadata:

```elixir
Telemetry.Metrics.sum("http.request.payload_size", tags: [:host, :method])
```

The above definiton means that we want to keep track of the sum, but for each unique pair of
request host and method (assuming that `:host` and `:method` keys are present in event's metadata).

There are four metric types provided by Telemetry.Metrics:

- counter, which counts the total number of emitted events
- sum which keeps track of the sum of selected measurement
- last value, holding the value of the selected measurement from the most recent event
- distribution, which builds a histogram of selected measurement

Note that the metric definitions themselves are not enough, as they only provide the specification
of what is the expected end-result. The job of subscribing to events and building the actual
metrics is a responsibility of reporters. This is the crucial part of this library design - it
doesn't aggregate events itself but relies on 3rd party reporters to perform this work in a way that
makes the most sense for a particular monitoring system.

See the documentation on [hexdocs](https://hexdocs.pm/telemetry_metrics/0.2.0) for more details.

## Copyright and License

Telemetry.Metrics is copyright (c) 2018 Chris McCord and Erlang Solutions.

Telemetry.Metrics source code is released under Apache License, Version 2.0.

See [LICENSE](LICENSE) and [NOTICE](NOTICE) files for more information.
