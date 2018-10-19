defmodule Telemetry.Metrics.MixProject do
  use Mix.Project

  def project do
    [
      app: :telemetry_metrics,
      version: "0.1.0",
      elixir: "~> 1.4",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib/", "test/support/"]
  defp elixirc_paths(_), do: ["lib/"]

  defp deps do
    [
      {:telemetry, "~> 0.2"}
    ]
  end
end
