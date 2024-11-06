defmodule OffBroadwayWebsocket.MixProject do
  use Mix.Project

  def project do
    [
      app:              :off_broadway_websocket,
      version:          "0.0.2",
      elixir:           "~> 1.16",
      start_permanent:  Mix.env() == :prod,
      deps:             deps(),
      description:      "An Off-Broadway producer enabling real-time ingestion of WebSocket data.",
      package:          [
        licenses:         ["Apache-2.0"],
        links:            %{"GitHub" => "https://github.com/mpol1t/off_broadway_websocket"}
      ]
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
      {:broadway,       "~> 1.1.0"},
      {:ex_doc,         "~> 0.34.2",  only: :dev,           runtime: false},
      {:dialyxir,       "~> 1.4",     only: [:dev, :test],  runtime: false},
      {:stream_data,    "~> 0.6",     only: [:dev, :test]}
    ]
  end
end
