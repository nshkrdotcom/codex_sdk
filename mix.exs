if bootstrap = System.get_env("MIX_WORKSPACE_OPS_BOOTSTRAP"), do: Code.require_file(bootstrap)

defmodule CodexSdk.MixProject do
  use Mix.Project

  @version "0.22.0"
  @source_url "https://github.com/nshkrdotcom/codex_sdk"
  @homepage_url "https://hex.pm/packages/codex_sdk"
  @docs_url "https://hexdocs.pm/codex_sdk"

  def project do
    [
      app: :codex_sdk,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      docs: docs(),
      description: description(),
      package: package(),
      name: "Codex SDK",
      source_url: @source_url,
      homepage_url: @homepage_url,
      test_coverage: [tool: ExCoveralls],
      test_ignore_filters: [&String.starts_with?(&1, "test/support/")],
      dialyzer: [
        plt_add_apps: [:mix],
        plt_core_path: "priv/plts/core",
        plt_local_path: "priv/plts",
        flags: [:error_handling, :underspecs]
      ]
    ]
  end

  def cli do
    [
      preferred_envs: [
        ci: :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      mod: {Codex.Application, []},
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      cli_subprocess_core_dep(),
      {:jason, "~> 1.4.5"},
      {:zoi, "~> 0.20.0"},
      {:typed_struct, "~> 0.3.0"},
      {:telemetry, "~> 1.4.3"},
      {:opentelemetry, "~> 1.7.0"},
      {:opentelemetry_exporter, "~> 1.11.0"},
      {:req, "~> 0.7.5"},
      {:oauth2, "~> 2.1.1"},
      {:plug, "~> 1.20.4"},
      {:bandit, "~> 1.15.0"},
      {:websockex, "~> 0.5.1"},
      {:toml, "~> 0.7.0"},
      {:supertester, "~> 0.6.0", only: :test},
      {:mox, "~> 1.3.2", only: :test},
      {:stream_data, "~> 1.4.0", only: :test},
      {:ex_doc, "~> 0.40.5", only: :dev, runtime: false},
      {:credo, "~> 1.7.19", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.9", only: [:dev], runtime: false},
      {:excoveralls, "~> 0.18.5", only: :test},
      {:castore, "~> 1.0.22", only: :test}
    ]
  end

  defp cli_subprocess_core_dep do
    workspace_dep({:cli_subprocess_core, "~> 0.10.3"})
  end

  defp description do
    """
    Elixir SDK for OpenAI's Codex agent with streaming turns, session resumption,
    and app-server support.
    """
  end

  defp docs do
    [
      main: "readme",
      name: "Codex SDK",
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @docs_url,
      assets: %{"assets" => "assets"},
      api_reference: false,
      filter_modules: fn _, _ -> false end,
      skip_code_autolink_to: &String.starts_with?(&1, ["Codex", "Mix.Tasks.Codex"]),
      logo: "assets/codex_sdk.svg",
      extras: [
        "README.md": [title: "Overview"],
        "guides/01-getting-started.md": [title: "Getting Started"],
        "guides/02-architecture.md": [title: "Architecture"],
        "guides/03-api-guide.md": [title: "API Guide"],
        "guides/04-examples.md": [title: "Examples"],
        "guides/05-app-server-transport.md": [title: "App Server Transport"],
        "guides/06-realtime-and-voice.md": [title: "Realtime And Voice"],
        "guides/07-models-and-reasoning.md": [title: "Models And Reasoning"],
        "guides/08-configuration-defaults.md": [title: "Configuration Defaults"],
        "guides/09-oauth-and-login.md": [title: "OAuth And Login"],
        "guides/10-subagents.md": [title: "Subagents"],
        "guides/11-typed-plugin-api.md": [title: "Typed Plugin API"],
        "guides/12-operational-workflows.md": [title: "Operational Workflows"],
        "guides/13-plugin-authoring.md": [title: "Plugin Authoring"],
        "guides/14-plugin-marketplaces.md": [title: "Plugin Marketplaces"],
        "guides/15-atom-safety.md": [title: "Atom Safety"],
        "guides/16-env-and-secrets.md": [title: "Environment And Secrets"],
        "guides/17-migrating-to-0.19.md": [title: "Migrating to 0.19"],
        "CHANGELOG.md": [title: "Changelog"],
        LICENSE: [title: "License"]
      ],
      groups_for_extras: [
        "Project Overview": ["README.md"],
        Foundations: [
          "guides/01-getting-started.md",
          "guides/02-architecture.md",
          "guides/03-api-guide.md"
        ],
        Capabilities: [
          "guides/04-examples.md",
          "guides/05-app-server-transport.md",
          "guides/06-realtime-and-voice.md",
          "guides/10-subagents.md",
          "guides/11-typed-plugin-api.md",
          "guides/12-operational-workflows.md",
          "guides/13-plugin-authoring.md",
          "guides/14-plugin-marketplaces.md",
          "guides/15-atom-safety.md",
          "guides/16-env-and-secrets.md",
          "guides/17-migrating-to-0.19.md"
        ],
        "Models & Configuration": [
          "guides/07-models-and-reasoning.md",
          "guides/08-configuration-defaults.md",
          "guides/09-oauth-and-login.md"
        ],
        Reference: ["CHANGELOG.md", "LICENSE"]
      ]
    ]
  end

  defp workspace_dep(committed) do
    if function_exported?(MixWorkspaceOpsBootstrap, :dep, 2),
      do: apply(MixWorkspaceOpsBootstrap, :dep, [committed, __DIR__]),
      else: committed
  end

  defp package do
    [
      name: "codex_sdk",
      description: description(),
      readme: "README.md",
      files: ~w(lib config assets guides examples mix.exs README.md CHANGELOG.md LICENSE VERSION),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Hex" => @homepage_url,
        "HexDocs" => @docs_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "License" => "#{@source_url}/blob/main/LICENSE",
        "OpenAI Codex" => "https://github.com/openai/codex"
      },
      maintainers: ["nshkrdotcom"],
      exclude_patterns: [
        "**/_build/**",
        "**/deps/**",
        "**/doc/**",
        "**/*.beam",
        "**/*.plt",
        "**/*.plt.hash",
        "priv/plts/**",
        "examples/_output/**",
        "examples/LIVE_EXAMPLES_PROMPT.md",
        "guides/provider_behavior_manifest.md",
        ".DS_Store"
      ]
    ]
  end

  defp aliases do
    [
      ci: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "cmd ./scripts/atom_guard.sh",
        "cmd ./scripts/secrets_guard.sh",
        "credo --strict",
        "test"
      ]
    ]
  end
end
