defmodule OffBroadwayWebsocket.MixProject do
  use Mix.Project

  def project do
    [
      app:             :off_broadway_websocket,
      version:         "1.0.2",
      elixir:          "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps:            deps(),
      description:     "An Off-Broadway producer enabling real-time ingestion of WebSocket data.",
      package:         [
        licenses: ["Apache-2.0"],
        links:    %{"GitHub" => "https://github.com/mpol1t/off_broadway_websocket"}
      ],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls:             :test,
        "coveralls.detail":    :test,
        "coveralls.post":      :test,
        "coveralls.html":      :test,
        "coveralls.cobertura": :test
      ]
    ]
  end

  def application do
    if Mix.env() == :prod do
      [extra_applications: [:logger]]
    else
      [extra_applications: [:logger, :mox]]
    end
  end

  defp deps do
    [
      {:gun,            "~> 2.1"},
      {:gen_stage,      "~> 1.3.0"},
      {:ssl_verify_fun, "~> 1.1"},
      {:castore,        "~> 1.0"},
      {:broadway,       "~> 1.2.0"},
      {:ex_doc,         "~> 0.38.1", only: [:dev],  runtime: false},
      {:eunomo,         "~> 3.0.0",  only: [:dev],  runtime: false},
      {:dialyxir,       "~> 1.4",    only: [:dev],  runtime: false},
      {:credo,          "~> 1.7",    only: [:dev],  runtime: false},
      {:styler,         "~> 1.9.0",  only: [:dev],  runtime: false},
      {:excoveralls,    "~> 0.18.3", only: [:test], runtime: false},
      {:meck,           "~> 1.0",    only: [:test], runtime: false},
      {:mox,            "~> 1.2",    only: [:test], runtime: false},
      {:stream_data,    "~> 1.1",    only: [:test], runtime: false}
    ]
  end
end
