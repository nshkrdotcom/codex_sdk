defmodule Codex.Realtime do
  @moduledoc """
  Realtime audio streaming with OpenAI's Realtime API.

  This module provides a high-level interface for building voice-enabled
  AI applications using WebSocket-based real-time communication.

  ## Quick Start

      # Define an agent
      agent = Codex.Realtime.agent(
        name: "VoiceAssistant",
        instructions: "You are a helpful voice assistant.",
        tools: [weather_tool]
      )

      # Create and run a session
      {:ok, session} = Codex.Realtime.run(agent)

      # Send audio and receive events
      Codex.Realtime.send_audio(session, audio_bytes)
      Codex.Realtime.subscribe(session, self())

      receive do
        {:session_event, event} -> handle_event(event)
      end

  ## Features

  - Real-time audio streaming (PCM16, G.711)
  - Voice activity detection (semantic VAD, server VAD)
  - Tool execution during conversations
  - Agent handoffs
  - Output guardrails
  - Dynamic instructions (string or function)

  ## Architecture

  The realtime feature consists of:

  - `Codex.Realtime.Agent` - Agent definition with tools and handoffs
  - `Codex.Realtime.Session` - Session management (GenServer)
  - `Codex.Realtime.Runner` - Session orchestration
  - `Codex.Realtime.Config` - Configuration types
  - `Codex.Realtime.Events` - Event types for subscribers
  - `Codex.Realtime.Items` - Conversation history items
  - `Codex.Realtime.Audio` - Audio format utilities

  ## Configuration

  Sessions can be configured with various options:

      {:ok, session} = Codex.Realtime.run(agent,
        config: %Codex.Realtime.Config.RunConfig{
          model_settings: %Codex.Realtime.Config.SessionModelSettings{
            voice: "nova",
            turn_detection: %Codex.Realtime.Config.TurnDetectionConfig{
              type: :semantic_vad,
              eagerness: :medium
            }
          }
        }
      )

  ## Event Handling

  Subscribers receive events as `{:session_event, event}` messages:

      Codex.Realtime.subscribe(session, self())

      receive do
        {:session_event, %Codex.Realtime.Events.AgentStartEvent{}} ->
          IO.puts("Agent started")

        {:session_event, %Codex.Realtime.Events.AudioEvent{audio: audio}} ->
          play_audio(audio.data)

        {:session_event, %Codex.Realtime.Events.ToolStartEvent{tool: tool}} ->
          IO.puts("Calling tool: \#{tool.name}")

        {:session_event, %Codex.Realtime.Events.AgentEndEvent{}} ->
          IO.puts("Turn completed")
      end

  """

  alias Codex.Realtime.Agent
  alias Codex.Realtime.Config
  alias Codex.Realtime.Config.ModelConfig
  alias Codex.Realtime.Runner
  alias Codex.Realtime.Session

  @doc """
  Create and start a realtime session with an agent.

  This is a convenience function that creates a runner and starts a session
  in one step. For more control, use `Codex.Realtime.Runner` directly.

  ## Options

    * `:config` - Run configuration (`%Codex.Realtime.Config.RunConfig{}`)
    * `:model_config` - Model connection config (`%Codex.Realtime.Config.ModelConfig{}`)
    * `:context` - Context map passed to the session

  ## Returns

    * `{:ok, pid}` - Session started successfully
    * `{:error, reason}` - Failed to start session

  ## Example

      {:ok, session} = Codex.Realtime.run(agent,
        config: %Codex.Realtime.Config.RunConfig{
          model_settings: %{voice: "nova"}
        }
      )

      # Use the session
      Codex.Realtime.send_message(session, "Hello!")
      Codex.Realtime.subscribe(session, self())
  """
  @spec run(Agent.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def run(agent, opts \\ []) do
    config = Keyword.get(opts, :config)
    model_config = Keyword.get(opts, :model_config, %ModelConfig{})
    context = Keyword.get(opts, :context, %{})

    # Pass through testing options
    websocket_pid = Keyword.get(opts, :websocket_pid)
    websocket_module = Keyword.get(opts, :websocket_module)

    runner = Runner.new(agent, config: config)

    runner_opts =
      [context: context, model_config: model_config]
      |> maybe_add_opt(:websocket_pid, websocket_pid)
      |> maybe_add_opt(:websocket_module, websocket_module)

    Runner.run(runner, runner_opts)
  end

  @doc """
  Create a realtime agent.

  This is a convenience function for creating an agent struct from keyword
  options.

  ## Options

    * `:name` - Agent name (default: "Agent")
    * `:instructions` - System instructions (string or function)
    * `:model` - Model name (default: "gpt-4o-realtime-preview")
    * `:tools` - List of tools available to the agent
    * `:handoffs` - List of agents or handoffs for transfers
    * `:output_guardrails` - Output guardrails to apply
    * `:hooks` - Event hooks

  ## Example

      agent = Codex.Realtime.agent(
        name: "Assistant",
        instructions: "Be helpful and concise.",
        tools: [my_tool],
        handoffs: [support_agent]
      )

      # With dynamic instructions
      agent = Codex.Realtime.agent(
        name: "Greeter",
        instructions: fn ctx -> "Hello \#{ctx.user_name}!" end
      )
  """
  @spec agent(keyword()) :: Agent.t()
  def agent(opts) do
    Agent.new(opts)
  end

  @doc """
  Create a runner for more control over session creation.

  Use this when you need to configure the runner separately from running it,
  or when you want to reuse the same runner for multiple sessions.

  ## Example

      runner = Codex.Realtime.runner(agent,
        config: %RunConfig{tracing_disabled: true}
      )

      {:ok, session1} = Codex.Realtime.Runner.run(runner)
      {:ok, session2} = Codex.Realtime.Runner.run(runner, context: %{user: "Alice"})
  """
  @spec runner(Agent.t(), keyword()) :: Runner.t()
  def runner(agent, opts \\ []) do
    Runner.new(agent, opts)
  end

  # Delegate session operations

  @doc """
  Send audio data to the model.

  ## Options

    * `:commit` - Whether to commit the audio buffer (default: false)

  ## Example

      Codex.Realtime.send_audio(session, audio_bytes)
      Codex.Realtime.send_audio(session, audio_bytes, commit: true)
  """
  @spec send_audio(GenServer.server(), binary(), keyword()) :: :ok
  defdelegate send_audio(session, audio, opts \\ []), to: Session

  @doc """
  Send a text message to the model.

  Can be a simple string or a structured message map.

  ## Example

      Codex.Realtime.send_message(session, "Hello!")

      Codex.Realtime.send_message(session, %{
        "type" => "message",
        "role" => "user",
        "content" => [%{"type" => "input_text", "text" => "Hello!"}]
      })
  """
  @spec send_message(GenServer.server(), String.t() | map()) :: :ok
  defdelegate send_message(session, message), to: Session

  @doc """
  Interrupt the current response.

  Sends a cancel signal to stop the model from generating more output.
  """
  @spec interrupt(GenServer.server()) :: :ok
  defdelegate interrupt(session), to: Session

  @doc """
  Subscribe to session events.

  The subscriber process will receive `{:session_event, event}` messages
  for all session events.

  ## Example

      Codex.Realtime.subscribe(session, self())

      receive do
        {:session_event, %Codex.Realtime.Events.AudioEvent{} = event} ->
          play_audio(event.audio.data)
      end
  """
  @spec subscribe(GenServer.server(), pid()) :: :ok
  defdelegate subscribe(session, pid), to: Session

  @doc """
  Get the conversation history.

  Returns all items in the conversation history.
  """
  @spec history(GenServer.server()) :: [Codex.Realtime.Items.item()]
  defdelegate history(session), to: Session

  @doc """
  Close the session.

  Closes the WebSocket connection and stops the session process.
  """
  @spec close(GenServer.server()) :: :ok
  defdelegate close(session), to: Session

  @doc """
  Unsubscribe from session events.
  """
  @spec unsubscribe(GenServer.server(), pid()) :: :ok
  defdelegate unsubscribe(session, pid), to: Session

  @doc """
  Send a raw event to the model.

  Use this for advanced scenarios where you need to send custom events.
  """
  @spec send_raw_event(GenServer.server(), map()) :: :ok
  defdelegate send_raw_event(session, event), to: Session

  @doc """
  Update session settings.

  Use this to change model settings mid-session, such as voice or modalities.

  ## Example

      settings = %Codex.Realtime.Config.SessionModelSettings{voice: "nova"}
      Codex.Realtime.update_session(session, settings)
  """
  @spec update_session(GenServer.server(), Config.SessionModelSettings.t()) :: :ok
  defdelegate update_session(session, settings), to: Session

  @doc """
  Get the current agent.
  """
  @spec current_agent(GenServer.server()) :: Agent.t()
  defdelegate current_agent(session), to: Session

  # Helpers

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)
end
