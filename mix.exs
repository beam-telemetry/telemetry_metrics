defmodule Telemetry.Metrics.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :telemetry_metrics,
      version: @version,
      elixir: "~> 1.5",
      start_permanent: Mix.env() == :prod,
      preferred_cli_env: preferred_cli_env(),
      deps: deps(),
      docs: docs(),
      description: description(),
      package: package(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp preferred_cli_env do
    [
      docs: :docs,
      dialyzer: :test,
      "coveralls.json": :test
    ]
  end

  defp deps do
    [
      {:telemetry, "~> 0.4"},
      {:ex_doc, "~> 0.19.0", only: :docs},
      {:dialyxir, "~> 1.0.0-rc.3", only: :test, runtime: false},
      {:excoveralls, "~> 0.10.0", only: :test, runtime: false}
    ]
  end

  defp docs do
    [
      main: "overview",
      canonical: "http://hexdocs.pm/telemetry_metrics",
      source_url: "https://github.com/beam-telemetry/telemetry_metrics",
      source_ref: "v#{@version}",
      extras: [
        "docs/overview.md",
        "docs/rationale.md",
        "docs/writing_reporters.md"
      ]
    ]
  end

  def description do
    """
    Defines data model and specifications for aggregating Telemetry events.
    """
  end

  defp package do
    [
      maintainers: ["Arkadiusz Gil", "José Valim"],
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/beam-telemetry/telemetry_metrics"}
    ]
  end
end
