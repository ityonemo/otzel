defmodule Otzel.MixProject do
  use Mix.Project

  def project do
    [
      app: :otzel,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp aliases do
    [
      test: "test --preload-modules",
      tidewave: "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4000) end)'"
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "support"]
  defp elixirc_paths(:perf), do: ["lib", "perf", "support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:protoss, "~> 1.1", runtime: false},
      {:zigler, "~> 0.15", runtime: false},
      {:diffy, "~> 1.1"},
      {:stream_data, "~> 1.0", only: [:test, :perf]},
      {:delta, "> 0.0.0", only: :perf},
      {:benchee, "> 0.0.0", only: :perf},
      {:tidewave, "~> 0.5", only: :dev},
      {:bandit, "~> 1.0", only: :dev}
    ]
  end

  def cli do
    [
      preferred_envs: ["otzel.perf": :perf]
    ]
  end
end
