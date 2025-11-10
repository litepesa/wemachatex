defmodule WemachatCore.MixProject do
  use Mix.Project

  def project do
    [
      app: :wemachat_core,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {WemachatCore.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:wemachat_database, in_umbrella: true},
      # HTTP client for M-Pesa API
      {:httpoison, "~> 2.0"},
      {:jason, "~> 1.2"}
    ]
  end
end
