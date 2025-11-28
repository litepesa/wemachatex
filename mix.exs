defmodule Wemachatex.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases()
    ]
  end

  defp deps do
    [
      {:dotenvy, "~> 0.8.0", only: [:dev, :test]}
    ]
  end

  defp releases do
    [
      wemachatex: [
        applications: [
          wemachat_database: :permanent,
          wemachat_core: :permanent,
          wemachat_api: :permanent
        ],
        include_executables_for: [:unix],
        steps: [:assemble, :tar]
      ]
    ]
  end
end
