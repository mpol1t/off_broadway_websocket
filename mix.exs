defmodule OffBroadwayWebsocket.MixProject do
  use Mix.Project

  def project do
    [
      app: :off_broadway_websocket,
      version: "0.2.1",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "An Off-Broadway producer enabling real-time ingestion of WebSocket data.",
      package: [
        licenses: ["Apache-2.0"],
        links: %{"GitHub" => "https://github.com/mpol1t/off_broadway_websocket"}
      ],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.cobertura": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    if Mix.env() == :prod do
      [extra_applications: [:logger]]
    else
      [extra_applications: [:logger, :mox]]
    end
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:gun, "~> 2.1"},
      {:gen_stage, "~> 1.2.1"},
      {:castore, "~> 1.0"},
      {:ssl_verify_fun, "~> 1.1"},
      {:broadway, "~> 1.2.0"},
      {:ex_doc, "~> 0.37.0", only: :dev, runtime: false},
      {:meck, "~> 1.0", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.2", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.1", only: [:dev, :test]},
      {:excoveralls, "~> 0.18.3", only: [:test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.4.0", only: [:dev, :test], runtime: false}
    ]
  end
end
