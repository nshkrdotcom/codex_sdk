<p align="center">
  <img src="assets/codex_sdk.svg" alt="Codex SDK Logo" width="200" height="200">
</p>

# Codex SDK for Elixir

[![CI](https://github.com/nshkrdotcom/codex_sdk/actions/workflows/elixir.yaml/badge.svg)](https://github.com/nshkrdotcom/codex_sdk/actions/workflows/elixir.yaml)
[![Elixir](https://img.shields.io/badge/elixir-1.18.3-purple.svg)](https://elixir-lang.org)
[![OTP](https://img.shields.io/badge/otp-27.3.3-blue.svg)](https://www.erlang.org)
[![Hex.pm](https://img.shields.io/hexpm/v/codex_sdk.svg)](https://hex.pm/packages/codex_sdk)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-purple.svg)](https://hexdocs.pm/codex_sdk)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/nshkrdotcom/codex_sdk/blob/main/LICENSE)

An idiomatic Elixir SDK for embedding OpenAI's Codex agent in your workflows and applications. This SDK wraps the `codex-rs` executable, providing a complete, production-ready interface with streaming support, comprehensive event handling, and robust testing utilities.

## Features

- **Complete Codex Integration**: Full-featured wrapper around the `codex-rs` CLI
- **Streaming & Non-Streaming**: Support for both real-time event streaming and buffered responses
- **Type Safety**: Comprehensive structs for all events, items, and options
- **OTP Native**: Built on GenServer for robust process management
- **Structured Output**: JSON schema support with automatic temporary file handling
- **Thread Management**: Create new conversations or resume existing sessions
- **Battle-Tested**: Comprehensive test suite using Supertester for deterministic OTP testing
- **Production Ready**: Robust error handling, supervision, and telemetry integration
- **Working Directory Controls**: Flexible sandbox modes and path management

## Installation

Add `codex_sdk` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:codex_sdk, "~> 0.1.0"}
  ]
end
```

## Prerequisites

You must have the `codex` CLI installed. Install it via npm or Homebrew:

```bash
# Using npm
npm install -g @openai/codex

# Using Homebrew
brew install codex
```

For authentication, sign in with your ChatGPT account:

```bash
codex
# Select "Sign in with ChatGPT"
```

See the [OpenAI Codex documentation](https://github.com/openai/codex) for more authentication options.

## Quick Start

### Basic Usage

```elixir
# Start a new conversation
{:ok, thread} = Codex.start_thread()

# Run a turn and get results
{:ok, result} = Codex.Thread.run(thread, "Explain the purpose of GenServers in Elixir")

# Access the final response
IO.puts(result.final_response)

# Inspect all items (messages, reasoning, commands, file changes, etc.)
IO.inspect(result.items)

# Continue the conversation
{:ok, next_result} = Codex.Thread.run(thread, "Give me an example")
```

### Streaming Responses

For real-time processing of events as they occur:

```elixir
{:ok, thread} = Codex.start_thread()

{:ok, stream} = Codex.Thread.run_streamed(
  thread,
  "Analyze this codebase and suggest improvements"
)

# Process events as they arrive
for event <- stream do
  case event do
    %Codex.Events.ItemStarted{item: item} ->
      IO.puts("New item: #{item.type}")

    %Codex.Events.ItemCompleted{item: %{type: "agent_message", text: text}} ->
      IO.puts("Response: #{text}")

    %Codex.Events.TurnCompleted{usage: usage} ->
      IO.puts("Tokens used: #{usage.input_tokens + usage.output_tokens}")

    _ ->
      :ok
  end
end
```

### Structured Output

Request JSON responses conforming to a specific schema:

```elixir
schema = %{
  "type" => "object",
  "properties" => %{
    "summary" => %{"type" => "string"},
    "issues" => %{
      "type" => "array",
      "items" => %{
        "type" => "object",
        "properties" => %{
          "severity" => %{"type" => "string", "enum" => ["low", "medium", "high"]},
          "description" => %{"type" => "string"},
          "file" => %{"type" => "string"}
        },
        "required" => ["severity", "description"]
      }
    }
  },
  "required" => ["summary", "issues"]
}

{:ok, thread} = Codex.start_thread()

{:ok, result} = Codex.Thread.run(
  thread,
  "Analyze the code quality of this project",
  output_schema: schema
)

# Parse the JSON response
{:ok, data} = Jason.decode(result.final_response)
IO.inspect(data["issues"])
```

### Resuming Threads

Threads are persisted in `~/.codex/sessions`. Resume previous conversations:

```elixir
thread_id = "thread_abc123"
{:ok, thread} = Codex.resume_thread(thread_id)

{:ok, result} = Codex.Thread.run(thread, "Continue from where we left off")
```

### Configuration Options

```elixir
# Codex-level options
codex_options = %Codex.Options{
  codex_path_override: "/custom/path/to/codex",
  base_url: "https://api.openai.com",
  api_key: System.get_env("OPENAI_API_KEY")
}

# Thread-level options
thread_options = %Codex.Thread.Options{
  model: "o1",
  sandbox_mode: true,
  working_directory: "/path/to/project",
  skip_git_repo_check: false
}

{:ok, thread} = Codex.start_thread(codex_options, thread_options)

# Turn-level options
turn_options = %Codex.Turn.Options{
  output_schema: my_json_schema
}

{:ok, result} = Codex.Thread.run(thread, "Your prompt", turn_options)
```

## Architecture

The SDK follows a layered architecture built on OTP principles:

- **`Codex`**: Main entry point for starting and resuming threads
- **`Codex.Thread`**: Manages individual conversation threads and turn execution
- **`Codex.Exec`**: GenServer that manages the `codex-rs` OS process via Port
- **`Codex.Events`**: Comprehensive event type definitions
- **`Codex.Items`**: Thread item structs (messages, commands, file changes, etc.)
- **`Codex.Options`**: Configuration structs for all levels
- **`Codex.OutputSchemaFile`**: Helper for managing JSON schema temporary files

### Process Model

```
┌─────────────┐
│   Client    │
└──────┬──────┘
       │
       ▼
┌─────────────────┐
│ Codex.Thread    │  (manages turn state)
└────────┬────────┘
         │
         ▼
┌──────────────────┐
│  Codex.Exec      │  (GenServer - manages codex-rs process)
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│   Port (stdin/   │  (IPC with codex-rs via JSONL)
│    stdout)       │
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│   codex-rs       │  (OpenAI's Codex CLI)
└──────────────────┘
```

## Event Types

The SDK provides structured events for all Codex operations:

### Thread Events

- `ThreadStarted` - New thread initialized with thread_id
- `TurnStarted` - Agent begins processing a prompt
- `TurnCompleted` - Turn finished with usage statistics
- `TurnFailed` - Turn encountered an error

### Item Events

- `ItemStarted` - New item added to thread
- `ItemUpdated` - Item state changed
- `ItemCompleted` - Item reached terminal state

### Item Types

- **`AgentMessage`** - Text or JSON response from the agent
- **`Reasoning`** - Agent's reasoning summary
- **`CommandExecution`** - Shell command execution with output
- **`FileChange`** - File modifications (add, update, delete)
- **`McpToolCall`** - Model Context Protocol tool invocations
- **`WebSearch`** - Web search queries and results
- **`TodoList`** - Agent's running task list
- **`Error`** - Non-fatal error items

## Testing

The SDK uses [Supertester](https://hex.pm/packages/supertester) for robust, deterministic OTP testing:

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run integration tests (requires codex CLI)
CODEX_TEST_LIVE=true mix test --include integration
```

### Test Features

- **Zero `Process.sleep`**: All tests use proper OTP synchronization
- **Fully Async**: All tests run with `async: true`
- **Mock Support**: Tests work with mocked `codex-rs` output
- **Live Testing**: Optional integration tests with real CLI
- **Chaos Engineering**: Resilience testing for process crashes
- **Performance Assertions**: SLA verification and leak detection

## Examples

See the `examples/` directory for comprehensive demonstrations:

- **`basic.exs`** - Simple conversation and streaming
- **`structured_output.exs`** - JSON schema usage
- **`multi_turn.exs`** - Extended conversations with context
- **`file_operations.exs`** - Watching file changes and commands
- **`error_handling.exs`** - Robust error recovery patterns

Run examples with:

```bash
mix run examples/basic.exs
```

## Documentation

Comprehensive documentation is available:

- **[API Reference](https://hexdocs.pm/codex_sdk)** - Complete module and function docs
- **[Architecture Guide](docs/02-architecture.md)** - System design and components
- **[Implementation Plan](docs/03-implementation-plan.md)** - Development roadmap
- **[Testing Strategy](docs/04-testing-strategy.md)** - TDD approach and patterns
- **[API Reference Doc](docs/05-api-reference.md)** - Detailed API specifications
- **[Examples Guide](docs/06-examples.md)** - Usage patterns and recipes

## Project Status

**Current Version**: 0.1.0 (In Development)

### MVP Roadmap

- [x] Project setup and structure
- [x] Documentation and design
- [ ] Core module implementation
- [ ] Event and item type definitions
- [ ] Exec GenServer with Port management
- [ ] Thread management and turn execution
- [ ] Streaming support
- [ ] Test suite with Supertester
- [ ] Examples and documentation
- [ ] CI/CD pipeline

See [docs/03-implementation-plan.md](docs/03-implementation-plan.md) for detailed progress.

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`mix test`)
5. Commit your changes (`git commit -m 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- OpenAI team for the Codex CLI and agent technology
- Elixir community for excellent OTP tooling and libraries
- [Gemini Ex](https://github.com/nshkrdotcom/gemini_ex) for SDK inspiration
- [Supertester](https://github.com/nshkrdotcom/supertester) for robust testing utilities

## Related Projects

- **[OpenAI Codex](https://github.com/openai/codex)** - The official Codex CLI
- **[Codex TypeScript SDK](https://github.com/openai/codex/tree/main/sdk/typescript)** - Official TypeScript SDK
- **[Gemini Ex](https://github.com/nshkrdotcom/gemini_ex)** - Elixir client for Google's Gemini AI

---

<p align="center">Made with ❤️ and Elixir</p>

