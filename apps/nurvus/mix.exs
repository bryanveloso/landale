defmodule Nurvus.MixProject do
  use Mix.Project

  def project do
    [
      app: :nurvus,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Nurvus.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:plug, "~> 1.14"},
      {:bandit, "~> 1.5"},
      {:req, "~> 0.4"},
      {:telemetry, "~> 1.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp releases do
    [
      nurvus: [
        version: "0.1.0",
        applications: [nurvus: :permanent],
        include_executables_for: [:unix, :windows],
        steps: [:assemble, :tar]
      ]
    ]
  end
end
