defmodule Codex.Realtime.Runner do
  @moduledoc """
  Orchestrates realtime agent sessions.

  A `Runner` is the equivalent of `Codex.AgentRunner` for realtime agents. It
  automatically handles multiple turns by maintaining a persistent connection
  with the underlying model layer.

  The session manages the local history copy, executes tools, runs guardrails
  and facilitates handoffs between agents.

  Since this code runs on your server, it uses WebSockets by default. You can
  optionally create your own custom model layer by implementing the
  `Codex.Realtime.Model` behaviour.

  ## Example

      # Create an agent
      agent = Codex.Realtime.Agent.new(
        name: "VoiceAssistant",
        instructions: "You are a helpful voice assistant."
      )

      # Create a runner
      runner = Codex.Realtime.Runner.new(agent,
        config: %Codex.Realtime.Config.RunConfig{
          tracing_disabled: false
        }
      )

      # Start a session
      {:ok, session} = Codex.Realtime.Runner.run(runner)

      # Use the session
      Codex.Realtime.Session.send_message(session, "Hello!")

      # Subscribe to events
      Codex.Realtime.Session.subscribe(session, self())
      receive do
        {:session_event, event} -> handle_event(event)
      end

  ## Options

  When creating a runner with `new/2`:

    * `:config` - A `%Codex.Realtime.Config.RunConfig{}` for runtime settings
    * `:model` - Optional custom model module implementing the Model behaviour

  When starting a session with `run/2`:

    * `:context` - Context map passed to the session
    * `:model_config` - A `%Codex.Realtime.Config.ModelConfig{}` for API settings
    * `:websocket_pid` - For testing with a mock WebSocket
    * `:websocket_module` - Override the WebSocket module (default: WebSockex)
  """

  alias Codex.Realtime.Agent
  alias Codex.Realtime.Config.ModelConfig
  alias Codex.Realtime.Config.RunConfig
  alias Codex.Realtime.Session

  defstruct [:starting_agent, :config, :model]

  @type t :: %__MODULE__{
          starting_agent: Agent.t() | nil,
          config: RunConfig.t() | nil,
          model: module() | nil
        }

  @doc """
  Create a new realtime runner.

  ## Arguments

    * `starting_agent` - The agent to start the session with.

  ## Options

    * `:config` - Override parameters to use for the entire run.
    * `:model` - The model to use. If not provided, will use the default
      OpenAI realtime model.

  ## Example

      agent = Codex.Realtime.Agent.new(name: "Assistant")
      runner = Codex.Realtime.Runner.new(agent,
        config: %Codex.Realtime.Config.RunConfig{tracing_disabled: true}
      )
  """
  @spec new(Agent.t(), keyword()) :: t()
  def new(starting_agent, opts \\ []) do
    %__MODULE__{
      starting_agent: starting_agent,
      config: Keyword.get(opts, :config),
      model: Keyword.get(opts, :model)
    }
  end

  @doc """
  Start a realtime session.

  Returns a session that can be used for bidirectional communication.

  ## Options

    * `:context` - Context to pass to the session (default: `%{}`)
    * `:model_config` - Model connection configuration (`%ModelConfig{}`)
    * `:websocket_pid` - For testing with a mock WebSocket
    * `:websocket_module` - Override the WebSocket module

  ## Returns

    * `{:ok, pid}` - Session started successfully
    * `{:error, reason}` - Failed to start session

  ## Example

      runner = Runner.new(agent)
      {:ok, session} = Runner.run(runner)

      # Send messages
      Session.send_message(session, "Hello!")

      # Stream events
      Session.subscribe(session, self())
      receive do
        {:session_event, event} -> handle_event(event)
      end

      # Close when done
      Session.close(session)
  """
  @spec run(t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def run(%__MODULE__{} = runner, opts \\ []) do
    context = Keyword.get(opts, :context, %{})
    model_config = Keyword.get(opts, :model_config, %ModelConfig{})

    # Pass through testing options
    websocket_pid = Keyword.get(opts, :websocket_pid)
    websocket_module = Keyword.get(opts, :websocket_module)

    session_opts =
      [
        agent: runner.starting_agent,
        config: model_config,
        run_config: runner.config || %RunConfig{},
        context: context
      ]
      |> maybe_add_opt(:websocket_pid, websocket_pid)
      |> maybe_add_opt(:websocket_module, websocket_module)

    Session.start_link(session_opts)
  end

  # Helpers

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)
end
