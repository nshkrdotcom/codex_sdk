# Realtime and Voice Guide

This guide covers:

1. **Realtime API** (`Codex.Realtime.*`) for bidirectional websocket sessions.
2. **Voice Pipeline** (`Codex.Voice.*`) for non-realtime STT -> workflow -> TTS.

Both paths make direct OpenAI API calls (they do not use `codex exec` / app-server transport).

## Auth and prerequisites

Realtime/Voice auth precedence:

1. `CODEX_API_KEY`
2. `auth.json` `OPENAI_API_KEY` (under `CODEX_HOME`)
3. `OPENAI_API_KEY`

`Codex.OAuth` does not replace this direct-API precedence. ChatGPT OAuth login
helps CLI/app-server flows; realtime and voice still need an API key or an
`OPENAI_API_KEY` persisted in `auth.json`.

If your account has no credits, direct API calls may return `insufficient_quota` (HTTP 429). If your account lacks access to realtime models, calls may fail with `model_not_found`. When the upstream Realtime service itself returns a generic `server_error`, the realtime examples now run a minimal raw-WebSocket probe first and print `SKIPPED` with the detected `session_id` so you can report the exact upstream failure cleanly.

`Codex.Realtime.Diagnostics.probe_text_turn/1` keeps that probe minimal and now
classifies `unknown_parameter`-style schema mismatches as a
`realtime_protocol_incompatible` skip reason instead of a hard failure. This
helps distinguish upstream schema drift from auth/quota/runtime failures.

Custom trust roots use `CODEX_CA_CERTIFICATE` first and `SSL_CERT_FILE` second. Blank values are
ignored. The same PEM bundle is applied to HTTPS requests and secure realtime websockets.

## Realtime API

### Core API surface

Use `Codex.Realtime.run/2` to start a session:

```elixir
alias Codex.Realtime
alias Codex.Realtime.Config.RunConfig
alias Codex.Realtime.Config.SessionModelSettings
alias Codex.Realtime.Config.TurnDetectionConfig

agent =
  Realtime.agent(
    name: "VoiceAssistant",
    instructions: "You are concise and helpful."
  )

config = %RunConfig{
  model_settings: %SessionModelSettings{
    voice: "alloy",
    turn_detection: %TurnDetectionConfig{
      type: :semantic_vad,
      eagerness: :medium
    }
  }
}

{:ok, session} = Realtime.run(agent, config: config)
Realtime.subscribe(session, self())
```

There is no `Realtime.start_session/2` or `Realtime.commit_audio/1`.  
Use `send_audio/3` with `commit: true` on the final chunk of a user turn.

### Sending user input

Text input:

```elixir
Realtime.send_message(session, "Hello from text input")
```

Audio input (commit on final chunk):

```elixir
chunks = [chunk1, chunk2, chunk3]
total = length(chunks)

chunks
|> Enum.with_index(1)
|> Enum.each(fn {chunk, idx} ->
  Realtime.send_audio(session, chunk, commit: idx == total)
end)
```

If you queue additional text input or tool output while a response is still
active, `Codex.Realtime.Session` defers the follow-up `response.create` until
the current response reaches `response.done`. That keeps overlapping turns from
issuing premature create requests.

### Receiving events

Realtime events are delivered as `{:session_event, event}`:

```elixir
alias Codex.Realtime.Events

receive do
  {:session_event, %Events.AgentStartEvent{agent: agent}} ->
    IO.puts("agent start: #{agent.name}")

  {:session_event, %Events.AudioEvent{audio: audio}} ->
    # audio.data is PCM bytes for output playback/storage
    File.write!("/tmp/realtime_output.pcm", audio.data, [:append])

  {:session_event, %Events.AudioEndEvent{}} ->
    IO.puts("audio segment completed")

  {:session_event, %Events.ToolStartEvent{tool: tool}} ->
    IO.puts("tool call: #{inspect(tool)}")

  {:session_event, %Events.ToolEndEvent{output: output}} ->
    IO.puts("tool output: #{output}")

  {:session_event, %Events.HandoffEvent{from_agent: from, to_agent: to}} ->
    IO.puts("handoff: #{from.name} -> #{to.name}")

  {:session_event, %Events.ErrorEvent{error: error}} ->
    IO.puts("realtime error: #{inspect(error)}")
end
```

### Handoffs

Configure handoffs directly on the realtime agent:

```elixir
support =
  Realtime.agent(
    name: "TechSupport",
    instructions: "Handle technical troubleshooting."
  )

greeter =
  Realtime.agent(
    name: "Greeter",
    instructions: "Route technical questions to TechSupport.",
    handoffs: [support]
  )
```

At session start, handoffs are exposed to the model as `transfer_to_*` function tools.  
When the model calls one, the session:

1. switches `current_agent`,
2. pushes updated session settings (`session.update`),
3. emits `%Events.HandoffEvent{}`,
4. sends tool output back to the model.

### Realtime debugging tips

If output audio is empty:

1. Confirm a voice is configured (`SessionModelSettings.voice`).
2. Confirm audio input boundaries are committed (`commit: true` on final chunk).
3. Log `%Events.ErrorEvent{}` and count `%Events.AudioEvent{}` deltas.
4. Check for quota/auth errors (`insufficient_quota`, unauthorized API key, etc.). Realtime `response.done` failures are surfaced as `%Events.ErrorEvent{}`.

If you see a generic Realtime `server_error`, try a raw health check first:

```elixir
case Codex.Realtime.Diagnostics.probe_text_turn(timeout_ms: 8_000) do
  {:ok, _proof} ->
    IO.puts("Realtime API responded to a minimal probe.")

  {:error, {:upstream_server_error, proof}} ->
    IO.puts(Codex.Realtime.Diagnostics.format_probe_failure(proof))
end
```

That probe bypasses `Codex.Realtime.Session` and the example logic entirely, so
it is useful for proving whether the failure is already present in the upstream
Realtime service.

### Session lifecycle helpers

`Codex.Realtime.Session` behavior exposed through `Codex.Realtime`:

- `subscribe/2` and `unsubscribe/2` are idempotent.
- `current_agent/1` returns the active agent (useful after handoff).
- `history/1` returns current item history.
- `close/1` stops the session.

## Voice Pipeline (non-realtime)

Use this path when you want STT -> custom workflow -> TTS, without a live websocket conversation loop.

```elixir
alias Codex.Voice.{Config, Pipeline, SimpleWorkflow}
alias Codex.Voice.Config.{STTSettings, TTSSettings}
alias Codex.Voice.Input.AudioInput

workflow =
  SimpleWorkflow.new(
    fn transcript -> ["You said: #{transcript}"] end,
    greeting: "Hello! I am listening."
  )

config = %Config{
  workflow_name: "voice_demo",
  stt_settings: %STTSettings{model: "gpt-4o-transcribe"},
  tts_settings: %TTSSettings{model: "gpt-4o-mini-tts", voice: :nova}
}

{:ok, pipeline} = Pipeline.start_link(workflow: workflow, config: config)
input = AudioInput.new(wav_binary, format: :wav)
{:ok, result_stream} = Pipeline.run(pipeline, input)

for event <- result_stream do
  case event do
    %Codex.Voice.Events.VoiceStreamEventAudio{data: audio_chunk} ->
      # play/store audio_chunk
      :ok

    %Codex.Voice.Events.VoiceStreamEventLifecycle{event: :session_ended} ->
      IO.puts("pipeline complete")

    %Codex.Voice.Events.VoiceStreamEventError{error: error} ->
      IO.puts("pipeline error: #{inspect(error)}")
  end
end
```

## Example scripts

Realtime:

```bash
mix run examples/realtime_basic.exs
mix run examples/realtime_tools.exs
mix run examples/realtime_handoffs.exs
mix run examples/live_realtime_voice.exs
```

Voice pipeline:

```bash
mix run examples/voice_pipeline.exs
mix run examples/voice_multi_turn.exs
mix run examples/voice_with_agent.exs
```

## Notes

- Realtime and Voice are direct API integrations; they do not rely on Codex CLI login tokens alone.
- `CODEX_CA_CERTIFICATE` takes precedence over `SSL_CERT_FILE` for HTTPS/WSS trust roots.
- Keep examples deterministic by setting voice and explicit audio turn boundaries.
- For CI or no-credit environments, treat `insufficient_quota` as a known skip condition for direct API demos.
- Realtime demos now also treat proven upstream `server_error` responses as a skip condition when the raw-WebSocket probe fails first.
