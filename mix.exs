defmodule CodexSdk.MixProject do
  use Mix.Project

  @version "0.15.0"
  @source_url "https://github.com/nshkrdotcom/codex_sdk"
  @homepage_url "https://hex.pm/packages/codex_sdk"
  @docs_url "https://hexdocs.pm/codex_sdk"
  @cli_subprocess_core_requirement "~> 0.1.0"
  @cli_subprocess_core_repo "nshkrdotcom/cli_subprocess_core"
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
      homepage_url: @homepage_url,
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
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      workspace_dep(
        :cli_subprocess_core,
        "../cli_subprocess_core",
        @cli_subprocess_core_requirement,
        github: @cli_subprocess_core_repo
      ),

      # Core dependencies
      {:jason, "~> 1.4"},
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
      homepage_url: @homepage_url,
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
        "guides/06-realtime-and-voice.md",
        "guides/07-models-and-reasoning.md",
        "guides/08-configuration-defaults.md",
        "guides/09-oauth-and-login.md",
        "guides/10-subagents.md"
      ],
      groups_for_extras: [
        Introduction: ["README.md", "guides/01-getting-started.md"],
        Guides: [
          "guides/02-architecture.md",
          "guides/05-app-server-transport.md",
          "guides/06-realtime-and-voice.md"
        ],
        Advanced: [
          "guides/07-models-and-reasoning.md",
          "guides/08-configuration-defaults.md",
          "guides/09-oauth-and-login.md",
          "guides/10-subagents.md"
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
          Codex.AppServer,
          Codex.AppServer.Account,
          Codex.CLI,
          Codex.CLI.Session,
          Codex.OAuth,
          Codex.OAuth.LoginResult,
          Codex.OAuth.Status,
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
      files: ~w(lib config priv guides assets mix.exs README.md CHANGELOG.md LICENSE VERSION),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Hex" => @homepage_url,
        "HexDocs" => @docs_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "OpenAI Codex" => "https://github.com/openai/codex"
      },
      maintainers: ["nshkrdotcom"],
      exclude_patterns: [
        "priv/plts",
        ".DS_Store"
      ]
    ]
  end

  defp workspace_dep(app, path, requirement, opts) do
    {release_opts, dep_opts} = Keyword.split(opts, [:github, :git, :branch, :tag, :ref])
    expanded_path = Path.expand(path, __DIR__)

    cond do
      hex_packaging?() ->
        {app, requirement, dep_opts}

      File.dir?(expanded_path) ->
        {app, Keyword.put(dep_opts, :path, path)}

      true ->
        {app, Keyword.merge(dep_opts, release_opts)}
    end
  end

  defp hex_packaging? do
    Enum.any?(System.argv(), &String.starts_with?(&1, "hex."))
  end
end
