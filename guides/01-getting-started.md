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
    {:codex_sdk, "~> 0.13.0"}
  ]
end
```

## Prerequisites

- Install the `codex` CLI (`npm install -g @openai/codex` or `brew install codex`).
- Authenticate with one of:
  - `CODEX_API_KEY`
  - `auth.json` `OPENAI_API_KEY`
  - Codex CLI login stored under `CODEX_HOME` (default `~/.codex`).

Native ChatGPT OAuth is also available from Elixir:

```elixir
{:ok, result} = Codex.OAuth.login(storage: :file, interactive?: true)
IO.inspect(result)
```

That flow writes upstream-compatible `auth.json` in persistent mode, keeps tokens
in memory when `storage: :memory`, prefers browser auth on local desktops,
falls back to device code on WSL/headless systems, and refuses to auto-start in
non-interactive environments such as CI.

For custom trust roots, set `CODEX_CA_CERTIFICATE` to a PEM bundle. If it is unset, the SDK falls
back to `SSL_CERT_FILE`. Blank values are ignored. This applies to Codex CLI subprocesses, direct
HTTP clients, remote model fetches, realtime websockets, MCP HTTP/OAuth, and voice requests.

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

If you leave web search untouched, the SDK now mirrors current Codex CLI defaults:

- cached web search for normal local runs
- live web search when you opt into full-access sandboxing

Use `web_search_mode: :disabled` or `web_search_enabled: false` only when you
need to override that default explicitly.

## CLI Passthrough

`Codex.CLI` exposes the literal terminal-client surface when you need a command
that does not fit the structured thread APIs.

```elixir
{:ok, codex_opts} = Codex.Options.new(%{})

{:ok, result} = Codex.CLI.completion("zsh", codex_opts: codex_opts)
IO.puts(result.stdout)

{:ok, session} =
  Codex.CLI.interactive(
    "Summarize this repository in three bullets.",
    codex_opts: codex_opts
  )

:ok = Codex.CLI.Session.close_input(session)
{:ok, session_result} = Codex.CLI.Session.collect(session)
IO.puts(session_result.stdout)
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

App-server is also where upstream `fs/*`, `plugin/read`, structured permissions approvals,
guardian review notifications, and `serverRequest/resolved` events are exposed.

When you need the managed app-server child to run against a temporary repo or
isolated `CODEX_HOME`, pass `cwd:` and `process_env:` to
`Codex.AppServer.connect/2`. Thread working directories are still configured per
thread.

You can also let `connect/2` manage child auth relative to that isolated child
environment:

```elixir
{:ok, conn} =
  Codex.AppServer.connect(codex_opts,
    experimental_api: true,
    process_env: %{"CODEX_HOME" => "/tmp/codex-home"},
    oauth: [mode: :auto, storage: :memory, auto_refresh: true]
  )
```

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
- `guides/09-oauth-and-login.md` for native OAuth, persistent vs memory auth, and WSL/headless behavior.
- `guides/06-realtime-and-voice.md` for voice interactions.
