defmodule CodexSdk.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/codex_sdk"

  def project do
    [
      app: :codex_sdk,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      description: description(),
      package: package(),
      name: "Codex SDK",
      source_url: @source_url,
      homepage_url: @source_url,
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      dialyzer: [
        plt_add_apps: [:mix],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        flags: [:error_handling, :underspecs],
        ignore_warnings: ".dialyzer_ignore.exs"
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :erlexec]
    ]
  end

  defp deps do
    [
      # Core dependencies
      {:jason, "~> 1.4"},
      {:typed_struct, "~> 0.3.0"},
      {:telemetry, "~> 1.3"},
      {:erlexec, "~> 2.0"},

      # Testing
      {:supertester, "~> 0.2.1", only: :test},
      {:mox, "~> 1.0", only: :test},
      {:stream_data, "~> 1.0", only: :test},

      # Development and documentation
      {:ex_doc, "~> 0.38.2", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp description do
    """
    Idiomatic Elixir SDK for OpenAI's Codex agent. Provides a complete, production-ready
    interface with streaming support, comprehensive event handling, and robust testing utilities.
    """
  end

  defp docs do
    [
      main: "readme",
      name: "Codex SDK",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @source_url,
      assets: %{"assets" => "assets"},
      logo: "assets/codex_sdk.svg",
      extras: [
        "README.md",
        "docs/01.md",
        "docs/02-architecture.md",
        "docs/03-implementation-plan.md",
        "docs/04-testing-strategy.md",
        "docs/05-api-reference.md",
        "docs/06-examples.md"
      ],
      groups_for_extras: [
        Introduction: ["README.md", "docs/01.md"],
        Design: [
          "docs/02-architecture.md",
          "docs/03-implementation-plan.md"
        ],
        Development: [
          "docs/04-testing-strategy.md",
          "docs/05-api-reference.md",
          "docs/06-examples.md"
        ]
      ],
      groups_for_modules: [
        "Core API": [Codex, Codex.Thread],
        Execution: [Codex.Exec, Codex.Telemetry],
        Files: [Codex.Files],
        Approvals: [Codex.Approvals, Codex.Approvals.Hook, Codex.Approvals.StaticPolicy],
        Tooling: [
          Codex.Tool,
          Codex.Tools,
          Codex.MCP.Client
        ],
        Errors: [
          Codex.Error,
          Codex.TransportError,
          Codex.ApprovalError
        ],
        Types: [
          Codex.Options,
          Codex.Thread.Options,
          Codex.Turn.Result
        ]
      ]
    ]
  end

  defp package do
    [
      name: "codex_sdk",
      description: description(),
      files: ~w(lib mix.exs README.md docs LICENSE assets),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Online documentation" => "https://hexdocs.pm/codex_sdk",
        "OpenAI Codex" => "https://github.com/openai/codex"
      },
      maintainers: ["nshkrdotcom"],
      exclude_patterns: [
        "priv/plts",
        ".DS_Store"
      ]
    ]
  end
end
