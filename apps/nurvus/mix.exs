defmodule Nurvus.MixProject do
  use Mix.Project

  def project do
    [
      app: :nurvus,
      version: "0.0.0",
      elixir: "~> 1.18",
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
      {:plug, "~> 1.14"},
      {:bandit, "~> 1.5"},
      {:req, "~> 0.4"},
      {:telemetry, "~> 1.0"},
      {:burrito, "~> 1.3"},
      {:jason, "~> 1.4"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end

  defp releases do
    [
      nurvus: [
        version: "2025.08.01b",
        applications: [nurvus: :permanent],
        include_executables_for: [:unix, :windows],
        steps: [:assemble, &Burrito.wrap/1],
        commands: [
          cli: "bin/nurvus_cli"
        ],
        burrito: [
          targets: [
            windows: [os: :windows, cpu: :x86_64],
            linux: [os: :linux, cpu: :x86_64],
            macos: [os: :darwin, cpu: :aarch64]
          ]
        ]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        release: :prod
      ]
    ]
  end
end
