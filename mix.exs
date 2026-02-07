defmodule CodexSdk.MixProject do
  use Mix.Project

  @version "0.7.0"
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
        flags: [:error_handling, :underspecs]
      ]
    ]
  end

  def application do
    [
      mod: {Codex.Application, []},
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
      {:opentelemetry, "~> 1.3"},
      {:opentelemetry_exporter, "~> 1.6"},
      {:req, "~> 0.4"},
      {:websockex, "~> 0.4.3"},

      # Testing
      {:supertester, "~> 0.5.1", only: :test},
      {:mox, "~> 1.0", only: :test},
      {:stream_data, "~> 1.0", only: :test},

      # Development and documentation
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
      source_ref: "v#{@version}",
      source_url: @source_url,
      homepage_url: @source_url,
      assets: %{"assets" => "assets"},
      logo: "assets/codex_sdk.svg",
      extras: [
        "README.md",
        "LICENSE",
        "CHANGELOG.md",
        "guides/01-getting-started.md",
        "guides/02-architecture.md",
        "guides/03-api-guide.md",
        "guides/04-examples.md",
        "guides/05-app-server-transport.md",
        "guides/06-realtime-and-voice.md"
      ],
      groups_for_extras: [
        Introduction: ["README.md", "guides/01-getting-started.md"],
        Guides: [
          "guides/02-architecture.md",
          "guides/05-app-server-transport.md",
          "guides/06-realtime-and-voice.md"
        ],
        Reference: [
          "guides/03-api-guide.md",
          "guides/04-examples.md",
          "LICENSE"
        ],
        Changelog: ["CHANGELOG.md"]
      ],
      groups_for_modules: [
        "Public API": [
          Codex,
          Codex.Thread,
          Codex.Thread.Options,
          Codex.Options,
          Codex.Turn.Result
        ],
        Execution: [
          Codex.Exec,
          Codex.Events,
          Codex.Items,
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
      files: ~w(lib config priv mix.exs README.md CHANGELOG.md LICENSE),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
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
