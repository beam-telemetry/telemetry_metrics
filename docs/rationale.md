# Rationale

The design proposed by Telemetry.Metrics might look controversial - unlike most of the libraries
available on the BEAM, it doesn't aggregate metrics itself, it merely defines what users should
expect when using the reporters.

If Telemetry.Metrics would aggregate metrics, the way those aggregations work would be imposed
on the system where the metrics are published to. For example, counters in StatsD are reset on
every flush and can be decremented, whereas counters in Prometheus are monotonically increasing.
Telemetry.Metrics doesn't focus on those details - instead, it describes what the end user,
operator, expects to see when using the metric of particular type. This implies that in most
cases aggregated metrics won't be visible inside the BEAM, but in exchange aggregations can be
implemented in a way that makes most sense for particular system.

Finally, one could also implement an in-VM "reporter" which would aggregate the metrics and expose
them inside the BEAM. When there is a need to swap the reporters, and if both reporters are
following the metric types specification, then the end result of aggregation is the same,
regardless of the backend system in use.