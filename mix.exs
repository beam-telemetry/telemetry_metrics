defmodule Telemetry.Metrics.MixProject do
  use Mix.Project

  def project do
    [
      app: :telemetry_metrics,
      version: "0.1.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env() == :prod,
      preferred_cli_env: preferred_cli_env(),
      deps: deps()
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
      dialyzer: :test
    ]
  end

  defp deps do
    [
      {:telemetry, "~> 0.3"},
      {:ex_doc, "~> 0.19.0", only: :docs},
      {:dialyxir, "~> 1.0.0-rc.3", only: :test, runtime: false}
    ]
  end
end
