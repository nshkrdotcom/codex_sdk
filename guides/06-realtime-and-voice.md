# Realtime and Voice Guide

This guide covers the Realtime API integration for bidirectional voice interactions and the Voice Pipeline for non-realtime STT -> Workflow -> TTS processing.

## Important: Architecture Note

The Realtime and Voice modules are **ported from the OpenAI Agents Python SDK** (`openai-agents-python`). Unlike the main Codex SDK features (`Codex.start_thread/2`, `Codex.resume_thread/3`), these modules make **direct API calls** to OpenAI rather than wrapping the `codex` CLI.

This means:
- **Realtime/Voice use API key auth via `Codex.Auth` precedence**:
  `CODEX_API_KEY` -> `auth.json` `OPENAI_API_KEY` -> `OPENAI_API_KEY`
- Realtime uses WebSocket connections to `wss://api.openai.com/v1/realtime`
- Voice uses HTTP calls to OpenAI's STT/TTS endpoints

## Overview

The Codex SDK provides two complementary approaches for voice-based interactions:

1. **Realtime API** (`Codex.Realtime.*`): Bidirectional WebSocket streaming for real-time voice conversations with the OpenAI Realtime API
2. **Voice Pipeline** (`Codex.Voice.*`): Non-realtime processing pipeline for speech-to-text, custom workflow execution, and text-to-speech

## Prerequisites

Both Realtime and Voice features require an OpenAI API key with access to the relevant models:

```bash
# Recommended
export CODEX_API_KEY=your-api-key-here

# Also supported
export OPENAI_API_KEY=your-api-key-here

# Or store OPENAI_API_KEY in auth.json under CODEX_HOME
```
`codex login` tokens alone are not used for these direct API paths.

For realtime examples with actual audio capture/playback, you'll need appropriate audio hardware and libraries.

---

## Realtime API

### Architecture

The Realtime API integration uses WebSocket-based bidirectional streaming:

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Your App      │────>│ Realtime.Session│────>│  OpenAI Realtime│
│                 │<────│   (WebSockex)   │<────│       API       │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │
        │                       ▼
        │               ┌─────────────────┐
        └──────────────>│ Realtime.Runner │
                        │  (Orchestrator) │
                        └─────────────────┘
```

### Key Components

- **`Codex.Realtime`**: Main module with agent builder and convenience functions
- **`Codex.Realtime.Session`**: WebSocket GenServer managing the connection
- **`Codex.Realtime.Runner`**: High-level orchestrator for agent sessions
- **`Codex.Realtime.Agent`**: Agent configuration struct
- **`Codex.Realtime.Events`**: Session and model event types

### Creating a Realtime Agent

```elixir
alias Codex.Realtime

# Simple agent
agent = Realtime.agent(
  name: "Assistant",
  instructions: "You are a helpful voice assistant."
)

# Agent with tools
agent_with_tools = Realtime.agent(
  name: "WeatherBot",
  instructions: "Help users check the weather.",
  tools: [
    %{
      name: "get_weather",
      description: "Get current weather for a location",
      parameters: %{
        type: "object",
        properties: %{
          location: %{type: "string", description: "City name"}
        },
        required: ["location"]
      }
    }
  ]
)
```

### Session Configuration

Configure session behavior with `RunConfig` and `SessionModelSettings`:

```elixir
alias Codex.Realtime.Config.{RunConfig, SessionModelSettings, TurnDetectionConfig}

config = %RunConfig{
  model_settings: %SessionModelSettings{
    # Voice options: alloy, ash, ballad, coral, echo, sage, shimmer, verse, marin, cedar
    voice: "alloy",

    # Turn detection configuration
    turn_detection: %TurnDetectionConfig{
      type: :semantic_vad,  # or :server_vad
      eagerness: :medium    # :low, :medium, :high
    }
  }
}
```

### Starting a Session

```elixir
# Start a realtime session
{:ok, session} = Realtime.start_session(agent, config)

# Subscribe to events
Realtime.subscribe(session, self())

# The session is now ready to send/receive audio
```

### Sending Audio

```elixir
# Send audio data (PCM16 format)
Realtime.send_audio(session, audio_data)

# Commit the audio buffer (signals end of user turn)
Realtime.commit_audio(session)
```

### Handling Events

```elixir
def handle_info({:realtime_event, event}, state) do
  case event do
    %Codex.Realtime.Events.RealtimeAudioEvent{audio: audio} ->
      # Play audio from the agent
      play_audio(audio)

    %Codex.Realtime.Events.RealtimeAgentStartEvent{} ->
      IO.puts("Agent started speaking")

    %Codex.Realtime.Events.RealtimeAgentStateEvent{state: agent_state} ->
      IO.puts("Agent state: #{agent_state}")

    %Codex.Realtime.Events.RealtimeToolCallEvent{name: name, args: args} ->
      # Handle tool call
      result = execute_tool(name, args)
      Realtime.send_tool_result(session, event.call_id, result)

    %Codex.Realtime.Events.RealtimeErrorEvent{error: error} ->
      Logger.error("Realtime error: #{inspect(error)}")

    _ ->
      :ok
  end

  {:noreply, state}
end
```

### Agent Handoffs

Transfer conversations between specialized agents:

```elixir
# Create specialized agents
greeter = Realtime.agent(
  name: "Greeter",
  instructions: "Welcome users and route to appropriate specialist."
)

tech_support = Realtime.agent(
  name: "TechSupport",
  instructions: "Provide technical assistance."
)

sales = Realtime.agent(
  name: "Sales",
  instructions: "Handle sales inquiries."
)

# Configure handoffs
greeter_with_handoffs = greeter
  |> Realtime.add_handoff(tech_support, condition: "Technical issues")
  |> Realtime.add_handoff(sales, condition: "Sales questions")

# Start session with the greeter
{:ok, session} = Realtime.start_session(greeter_with_handoffs, config)
```

### Session Lifecycle

Session behavior notes:
- `subscribe/2` and `unsubscribe/2` are idempotent.
- Tool execution runs outside the session callback path so other session messages stay responsive.
- WebSocket process exits are trapped and surfaced as session error events; the session process does not crash from linked socket exits.

```elixir
# Stop the session
Realtime.stop_session(session)

# Or let it timeout/disconnect naturally
```

---

## Voice Pipeline

### Architecture

The Voice Pipeline processes audio in stages:

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│ Audio Input │────>│     STT     │────>│  Workflow   │────>│     TTS     │
│             │     │ (Transcribe)│     │ (Process)   │     │ (Synthesize)│
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
                                                                    │
                                                                    ▼
                                                            ┌─────────────┐
                                                            │Audio Output │
                                                            │  (Stream)   │
                                                            └─────────────┘
```

### Key Components

- **`Codex.Voice.Pipeline`**: Main orchestrator for the STT -> Workflow -> TTS flow
- **`Codex.Voice.Workflow`**: Behaviour for custom processing logic
- **`Codex.Voice.SimpleWorkflow`**: Simple function-based workflow
- **`Codex.Voice.AgentWorkflow`**: Workflow backed by `Codex.Agent`
- **`Codex.Voice.Input.AudioInput`**: Single audio buffer input
- **`Codex.Voice.Input.StreamedAudioInput`**: Streaming audio input
- **`Codex.Voice.Result`**: Streamed audio output

### Simple Workflow

For basic request-response patterns:

```elixir
alias Codex.Voice.{SimpleWorkflow, Config, Pipeline}

# Create a workflow with a handler function
workflow = SimpleWorkflow.new(
  fn transcribed_text ->
    # Process the text and return response(s)
    ["I understood: #{transcribed_text}. How can I help?"]
  end,
  greeting: "Hello! I'm listening."
)
```

### Agent Workflow

For multi-turn conversations backed by a Codex agent:

```elixir
alias Codex.Voice.AgentWorkflow

workflow = AgentWorkflow.new(
  agent: %{
    instructions: """
    You are a helpful coding assistant accessible via voice.
    Keep responses concise and clear for audio delivery.
    """,
    tools: [Codex.Tools.FileSearchTool]
  }
)
```

### Pipeline Configuration

```elixir
alias Codex.Voice.Config
alias Codex.Voice.Config.{STTSettings, TTSSettings}

config = %Config{
  workflow_name: "MyVoiceAssistant",

  # Speech-to-text settings
  stt_settings: %STTSettings{
    model: "gpt-4o-transcribe"
  },

  # Text-to-speech settings
  tts_settings: %TTSSettings{
    model: "gpt-4o-mini-tts",
    voice: :nova  # :alloy, :echo, :fable, :onyx, :nova, :shimmer
  }
}
```

### Running the Pipeline

#### Single-Turn Processing

```elixir
alias Codex.Voice.Pipeline
alias Codex.Voice.Input.AudioInput

# Start the pipeline
{:ok, pipeline} = Pipeline.start_link(
  workflow: workflow,
  config: config
)

# Create audio input (WAV format)
input = AudioInput.new(audio_data, format: :wav)

# Run the pipeline
{:ok, result} = Pipeline.run(pipeline, input)

# Process the streamed audio output
for event <- result do
  case event do
    %Codex.Voice.Events.VoiceStreamEventAudio{data: audio_chunk} ->
      play_audio(audio_chunk)

    %Codex.Voice.Events.VoiceStreamEventLifecycle{event: :completed} ->
      IO.puts("Processing complete")

    %Codex.Voice.Events.VoiceStreamEventError{error: error} ->
      Logger.error("Error: #{inspect(error)}")

    _ ->
      :ok
  end
end
```

#### Multi-Turn Streaming

```elixir
alias Codex.Voice.Input.StreamedAudioInput

# Create streaming input
input = StreamedAudioInput.new()

# Start streaming processing
{:ok, result_stream} = Pipeline.run_streamed(pipeline, input)

# Feed audio chunks in a separate task
Task.start(fn ->
  for chunk <- audio_source do
    StreamedAudioInput.push(input, chunk)
  end
  StreamedAudioInput.close(input)
end)

# Process results as they arrive
for event <- result_stream do
  handle_voice_event(event)
end
```

### Custom Workflow Implementation

Implement the `Codex.Voice.Workflow` behaviour for custom processing:

```elixir
defmodule MyCustomWorkflow do
  @behaviour Codex.Voice.Workflow

  defstruct [:state, :greeting]

  @impl true
  def new(opts) do
    %__MODULE__{
      state: opts[:initial_state] || %{},
      greeting: opts[:greeting]
    }
  end

  @impl true
  def greeting(%__MODULE__{greeting: greeting}), do: greeting

  @impl true
  def run(%__MODULE__{} = workflow, input_text) do
    # Process input and generate response(s)
    responses = process_input(input_text, workflow.state)

    # Return list of response strings
    {:ok, responses, workflow}
  end

  defp process_input(text, state) do
    # Your custom logic here
    ["Processed: #{text}"]
  end
end
```

### Audio Formats

The pipeline supports various audio formats:

```elixir
# WAV format (recommended for recordings)
input = AudioInput.new(wav_data, format: :wav)

# Raw PCM16
input = AudioInput.new(pcm_data, format: :pcm16, sample_rate: 16000)

# The pipeline auto-detects WAV headers when format is not specified
input = AudioInput.new(audio_data)
```

### Collecting Audio Output

```elixir
# Collect all audio chunks
audio_output = result
  |> Enum.filter(&match?(%Codex.Voice.Events.VoiceStreamEventAudio{}, &1))
  |> Enum.map(& &1.data)
  |> IO.iodata_to_binary()

# Save to file
File.write!("output.wav", Codex.Voice.WAV.encode(audio_output))
```

---

## Telemetry Events

Both Realtime and Voice emit telemetry events for observability:

### Realtime Events

```elixir
# Session lifecycle
[:codex, :realtime, :session, :start]
[:codex, :realtime, :session, :stop]
[:codex, :realtime, :session, :error]

# Audio events
[:codex, :realtime, :audio, :sent]
[:codex, :realtime, :audio, :received]

# Tool calls
[:codex, :realtime, :tool, :call]
[:codex, :realtime, :tool, :result]
```

### Voice Pipeline Events

```elixir
# Pipeline lifecycle
[:codex, :voice, :pipeline, :start]
[:codex, :voice, :pipeline, :stop]

# STT events
[:codex, :voice, :stt, :start]
[:codex, :voice, :stt, :complete]

# TTS events
[:codex, :voice, :tts, :start]
[:codex, :voice, :tts, :chunk]
[:codex, :voice, :tts, :complete]
```

### Attaching Handlers

```elixir
:telemetry.attach_many(
  "voice-handler",
  [
    [:codex, :voice, :pipeline, :start],
    [:codex, :voice, :pipeline, :stop],
    [:codex, :realtime, :session, :start]
  ],
  fn event, measurements, metadata, _config ->
    Logger.info("#{inspect(event)}: #{inspect(measurements)}")
  end,
  nil
)
```

---

## Examples

The SDK includes comprehensive examples for both Realtime and Voice:

### Realtime Examples

```bash
# Basic session setup
mix run examples/realtime_basic.exs

# Function tools with realtime
mix run examples/realtime_tools.exs

# Multi-agent handoffs
mix run examples/realtime_handoffs.exs

# Full interactive demo
mix run examples/live_realtime_voice.exs
```

### Voice Pipeline Examples

```bash
# Basic STT -> Workflow -> TTS
mix run examples/voice_pipeline.exs

# Multi-turn conversations
mix run examples/voice_multi_turn.exs

# Agent-backed voice
mix run examples/voice_with_agent.exs
```

---

## Best Practices

### Realtime

1. **Handle disconnections**: The WebSocket may disconnect; implement reconnection logic
2. **Monitor latency**: Use telemetry to track round-trip times
3. **Buffer audio**: Send audio in reasonable chunks (e.g., 200ms)
4. **Use semantic VAD**: Provides better turn detection than server VAD

### Voice Pipeline

1. **Streaming for long audio**: Use `StreamedAudioInput` for audio longer than a few seconds
2. **Keep responses concise**: Shorter responses work better for voice
3. **Handle errors gracefully**: The pipeline may fail at any stage
4. **Cache workflows**: Reuse `AgentWorkflow` instances for multi-turn conversations

### General

1. **Test with real audio**: Synthetic test audio may not represent real-world conditions
2. **Monitor costs**: Both STT and TTS incur API costs
3. **Respect rate limits**: OpenAI APIs have rate limits
4. **Handle silence**: Users may pause; configure appropriate timeouts

---

## Troubleshooting

### Common Issues

**WebSocket connection fails**
- Check API key validity
- Verify network connectivity
- Check for firewall restrictions on WebSocket connections

**Audio not transcribed correctly**
- Ensure audio is in a supported format (WAV, PCM16)
- Check sample rate matches what the API expects (usually 16kHz)
- Verify audio quality (minimize background noise)

**TTS output sounds robotic**
- Try different voice options
- Adjust text for better prosody (shorter sentences, punctuation)

**High latency**
- Check network conditions
- Consider geographic proximity to API servers
- Use streaming for faster first-byte response

### Debug Logging

Enable debug logging for troubleshooting:

```elixir
# In config/config.exs
config :logger, level: :debug

# Or at runtime
Logger.configure(level: :debug)
```
