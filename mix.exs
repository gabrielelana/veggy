defmodule Veggy.Mixfile do
  use Mix.Project

  def project do
    [app: :veggy,
     version: "0.1.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  def application do
    [applications: [:logger, :cowboy, :plug],
     mod: {Veggy, []}]
  end

  defp deps do
    [{:cowboy, "~> 1.0"},
     {:plug, "~> 1.2.0-rc.0"}]
  end
end
