defmodule OffBroadwayWebsocket.MixProject do
  use Mix.Project

  def project do
    [
      app:              :off_broadway_websocket,
      version:          "0.0.1",
      elixir:           "~> 1.16",
      start_permanent:  Mix.env() == :prod,
      deps:             deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:gun,            "~> 2.1"},
      {:gen_stage,      "~> 1.2.1"},
      {:castore,        "~> 1.0"},
      {:ssl_verify_fun, "~> 1.1"},
      {:jason,          "~> 1.4"},
      {:broadway,       "~> 1.1.0"},
      {:dialyxir,       "~> 1.4", only: [:dev, :test], runtime: false},
      {:stream_data,    "~> 0.6", only: [:dev, :test]},
    ]
  end
end