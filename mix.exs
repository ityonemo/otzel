defmodule Otzel.MixProject do
  use Mix.Project

  @version "0.3.0"
  @source_url "https://github.com/ityonemo/otzel"

  def project do
    [
      app: :otzel,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      aliases: aliases(),
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url
    ]
  end

  defp description do
    "An Elixir library for Operational Transformation (OT) using the Delta format."
  end

  defp package do
    [
      name: "otzel",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "Otzel",
      source_ref: "v#{@version}",
      source_url: @source_url
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
      tidewave:
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4000) end)'"
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "support"]
  defp elixirc_paths(:perf), do: ["lib", "perf", "support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ecto, "~> 3.0", optional: Mix.env() == :prod},
      {:protoss, "~> 1.1", runtime: false},
      {:diffy, "~> 1.1", only: :perf},
      {:stream_data, "~> 1.0", only: [:test, :perf]},
      {:delta, "> 0.0.0", only: :perf},
      {:benchee, "> 0.0.0", only: :perf},
      {:tidewave, "~> 0.5", only: :dev},
      {:bandit, "~> 1.0", only: :dev},
      {:ex_doc, "~> 0.35", only: :dev, runtime: false}
    ]
  end

  def cli do
    [
      preferred_envs: ["otzel.perf": :perf]
    ]
  end
end
