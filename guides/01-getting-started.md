# Getting Started

## Overview

Codex SDK for Elixir wraps the Codex CLI (`codex`) and provides an idiomatic API for
starting threads, streaming turns, and integrating tools. It runs as a subprocess
and communicates over JSONL (exec) or JSON-RPC (app-server).

## Install

Add the dependency in `mix.exs`:

```elixir
def deps do
  [
    {:codex_sdk, "~> 0.9.0"}
  ]
end
```

## Prerequisites

- Install the `codex` CLI (`npm install -g @openai/codex` or `brew install codex`).
- Authenticate with one of:
  - `CODEX_API_KEY`
  - `auth.json` `OPENAI_API_KEY`
  - Codex CLI login stored under `CODEX_HOME` (default `~/.codex`).

The SDK resolves the executable in this order:
1. `codex_path_override` in `Codex.Options`
2. `CODEX_PATH`
3. `System.find_executable("codex")`

## Quick Start

```elixir
{:ok, thread} = Codex.start_thread()
{:ok, result} = Codex.Thread.run(thread, "Summarize this repository")
IO.puts(result.final_response)
```

## Streaming

```elixir
{:ok, thread} = Codex.start_thread()
{:ok, stream} = Codex.Thread.run_streamed(thread, "Explain GenServers")

for event <- stream do
  IO.inspect(event)
end
```

## Structured Output

```elixir
schema = %{
  "type" => "object",
  "properties" => %{
    "summary" => %{"type" => "string"},
    "key_points" => %{
      "type" => "array",
      "items" => %{"type" => "string"}
    }
  },
  "required" => ["summary", "key_points"]
}

{:ok, thread} = Codex.start_thread()
{:ok, result} = Codex.Thread.run(thread, "Summarize this repo", output_schema: schema)
{:ok, data} = Jason.decode(result.final_response)
IO.inspect(data["key_points"])
```

## Personality and Web Search

You can set per-thread defaults for personality and web search mode:

```elixir
{:ok, thread_opts} =
  Codex.Thread.Options.new(%{
    personality: :friendly,
    web_search_mode: :cached
  })

{:ok, thread} = Codex.start_thread(%Codex.Options{}, thread_opts)
{:ok, result} = Codex.Thread.run(thread, "Summarize the latest release notes")
IO.puts(result.final_response)
```

## Sessions

Threads are persisted by the Codex CLI under `~/.codex/sessions`. You can list
and resume them:

```elixir
{:ok, sessions} = Codex.list_sessions()
{:ok, thread} = Codex.resume_thread(:last)
```

## Transports

- **Exec JSONL (default):** `codex exec --json` for a simple subprocess flow.
- **App-server JSON-RPC (optional):** `codex app-server` for v2 APIs and server-driven
  approvals.

See `guides/05-app-server-transport.md` for the app-server guide.

## Realtime and Voice

For voice-based interactions, the SDK provides two options:

### Realtime API (Bidirectional Streaming)

```elixir
alias Codex.Realtime

agent = Realtime.agent(name: "Assistant", instructions: "You are helpful.")
{:ok, session} = Realtime.run(agent)
Realtime.subscribe(session, self())
Realtime.send_audio(session, audio_data, commit: true)
```

### Voice Pipeline (STT -> Workflow -> TTS)

```elixir
alias Codex.Voice.{Pipeline, SimpleWorkflow, Config}

workflow = SimpleWorkflow.new(fn text -> ["You said: #{text}"] end)
{:ok, pipeline} = Pipeline.start_link(workflow: workflow, config: %Config{})
{:ok, result} = Pipeline.run(pipeline, audio_input)
```

See `guides/06-realtime-and-voice.md` for the complete guide.

## Next Steps

- `guides/02-architecture.md` for system layout and transport flow.
- `guides/03-api-guide.md` for module-level docs.
- `guides/04-examples.md` for runnable patterns.
- `guides/06-realtime-and-voice.md` for voice interactions.
