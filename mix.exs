defmodule CodexSdk.MixProject do
  use Mix.Project

  def project do
    [
      app: :codex_sdk,
      version: "0.16.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      description: description(),
      package: package(),
      name: "Codex SDK",
      source_url: "https://github.com/nshkrdotcom/codex_sdk",
      homepage_url: "https://hex.pm/packages/codex_sdk",
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      dialyzer: [
        plt_add_apps: [:mix],
        plt_core_path: "priv/plts/core",
        plt_local_path: "priv/plts",
        flags: [:error_handling, :underspecs]
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
      {:cli_subprocess_core, "~> 0.1.0"},
      {:jason, "~> 1.4"},
      {:zoi, "~> 0.17"},
      {:typed_struct, "~> 0.3.0"},
      {:telemetry, "~> 1.3"},
      {:opentelemetry, "~> 1.3"},
      {:opentelemetry_exporter, "~> 1.6"},
      {:req, "~> 0.4"},
      {:oauth2, "~> 2.1"},
      {:plug, "~> 1.16"},
      {:bandit, "~> 1.5"},
      {:websockex, "~> 0.5.1"},
      {:toml, "~> 0.7"},
      {:supertester, "~> 0.5.1", only: :test},
      {:mox, "~> 1.2", only: :test},
      {:stream_data, "~> 1.1", only: :test},
      {:ex_doc, "~> 0.40.0", only: :dev, runtime: false},
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
      source_ref: "v0.16.0",
      source_url: "https://github.com/nshkrdotcom/codex_sdk",
      homepage_url: "https://hex.pm/packages/codex_sdk",
      assets: %{"assets" => "assets"},
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
        "guides/13-plugin-authoring.md": [title: "Plugin Authoring"],
        "guides/14-plugin-marketplaces.md": [title: "Plugin Marketplaces"],
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
          "guides/13-plugin-authoring.md",
          "guides/14-plugin-marketplaces.md"
        ],
        "Models & Configuration": [
          "guides/07-models-and-reasoning.md",
          "guides/08-configuration-defaults.md",
          "guides/09-oauth-and-login.md"
        ],
        Reference: ["CHANGELOG.md", "LICENSE"]
      ],
      groups_for_modules: [
        "Public API": [
          Codex,
          Codex.AppServer,
          Codex.AppServer.Account,
          Codex.CLI,
          Codex.CLI.Session,
          Codex.OAuth,
          Codex.OAuth.LoginResult,
          Codex.OAuth.Status,
          Codex.Plugins,
          Codex.Plugins.Manifest,
          Codex.Plugins.Marketplace,
          Codex.Subagents,
          Codex.Thread,
          Codex.Thread.Options,
          Codex.Options,
          Codex.Models,
          Codex.Turn.Result
        ],
        Configuration: [
          Codex.Config.Defaults,
          Codex.Config.BaseURL,
          Codex.Config.Overrides,
          Codex.Config.OptionNormalizers
        ],
        Execution: [
          Codex.Exec,
          Codex.Events,
          Codex.Items,
          Codex.Protocol.CollabAgentRef,
          Codex.Protocol.CollabAgentState,
          Codex.Protocol.CollabAgentStatusEntry,
          Codex.Protocol.SessionSource,
          Codex.Protocol.SubAgentSource,
          Codex.Telemetry
        ],
        Files: [
          Codex.Files,
          Codex.Files.Registry,
          Codex.OutputSchemaFile
        ],
        Approvals: [
          Codex.Approvals,
          Codex.Approvals.Registry,
          Codex.Approvals.Hook,
          Codex.Approvals.StaticPolicy,
          Codex.ApprovalError
        ],
        Tooling: [
          Codex.Tool,
          Codex.Tools,
          Codex.Tools.Registry,
          Codex.MCP.Client,
          Codex.MCP.Config,
          Codex.MCP.OAuth,
          Codex.MCP.Transport.Stdio,
          Codex.MCP.Transport.StreamableHTTP,
          Codex.Prompts,
          Codex.Skills
        ],
        Errors: [
          Codex.Error,
          Codex.TransportError
        ],
        Realtime: [
          Codex.Realtime,
          Codex.Realtime.Agent,
          Codex.Realtime.Diagnostics,
          Codex.Realtime.Audio,
          Codex.Realtime.Config,
          Codex.Realtime.Config.GuardrailsSettings,
          Codex.Realtime.Config.ModelConfig,
          Codex.Realtime.Config.NoiseReductionConfig,
          Codex.Realtime.Config.RunConfig,
          Codex.Realtime.Config.SessionModelSettings,
          Codex.Realtime.Config.TracingConfig,
          Codex.Realtime.Config.TranscriptionConfig,
          Codex.Realtime.Config.TurnDetectionConfig,
          Codex.Realtime.Events,
          Codex.Realtime.Items,
          Codex.Realtime.Model,
          Codex.Realtime.ModelEvents,
          Codex.Realtime.ModelInputs,
          Codex.Realtime.OpenAIWebSocket,
          Codex.Realtime.PlaybackTracker,
          Codex.Realtime.Runner,
          Codex.Realtime.Session
        ],
        Voice: [
          Codex.Voice,
          Codex.Voice.AgentWorkflow,
          Codex.Voice.Config,
          Codex.Voice.Config.STTSettings,
          Codex.Voice.Config.TTSSettings,
          Codex.Voice.Events,
          Codex.Voice.Input,
          Codex.Voice.Input.AudioInput,
          Codex.Voice.Input.StreamedAudioInput,
          Codex.Voice.Model,
          Codex.Voice.Models.OpenAIProvider,
          Codex.Voice.Models.OpenAISTT,
          Codex.Voice.Models.OpenAITTS,
          Codex.Voice.Pipeline,
          Codex.Voice.Result,
          Codex.Voice.SimpleWorkflow,
          Codex.Voice.Workflow
        ],
        Tasks: [
          Mix.Tasks.Codex.Parity,
          Mix.Tasks.Codex.Verify
        ]
      ]
    ]
  end

  defp package do
    [
      name: "codex_sdk",
      description: description(),
      readme: "README.md",
      files:
        ~w(lib config priv/models.json assets mix.exs README.md CHANGELOG.md LICENSE VERSION),
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/nshkrdotcom/codex_sdk",
        "Hex" => "https://hex.pm/packages/codex_sdk",
        "HexDocs" => "https://hexdocs.pm/codex_sdk",
        "Changelog" => "https://github.com/nshkrdotcom/codex_sdk/blob/main/CHANGELOG.md",
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
