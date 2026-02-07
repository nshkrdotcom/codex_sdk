# Examples and Usage Patterns

This document provides comprehensive examples demonstrating common use cases and patterns for the Elixir Codex SDK. Runnable counterparts live under `/examples`; each script can be executed with `mix run examples/<name>.exs ...`.

Auth defaults: all examples prefer `CODEX_API_KEY` (or `auth.json` `OPENAI_API_KEY`) when present; otherwise they fall back to your Codex CLI login stored under `CODEX_HOME` (default `~/.codex`).

## Table of Contents

1. [Basic Usage](#basic-usage)
2. [Streaming Responses](#streaming-responses)
3. [Structured Output](#structured-output)
4. [Multi-Turn Conversations](#multi-turn-conversations)
5. [File Operations](#file-operations)
6. [Command Execution](#command-execution)
7. [Error Handling](#error-handling)
8. [Configuration](#configuration)
9. [Advanced Patterns](#advanced-patterns)
10. [Production Patterns](#production-patterns)
11. [Live Usage & Compaction](#live-usage--compaction)
12. [Live Exec Controls](#live-exec-controls)
13. [Live Telemetry Stream](#live-telemetry-stream)
14. [Additional Live Examples](#additional-live-examples)
15. [App-server Transport](#app-server-transport)
16. [Realtime Voice Interactions](#realtime-voice-interactions)
17. [Voice Pipeline](#voice-pipeline)

---

## Basic Usage

### Simple Question and Answer

The most basic usage: ask a question and get a response.

```elixir
defmodule BasicExample do
  def ask_question do
    # Start a new thread
    {:ok, thread} = Codex.start_thread()

    # Run a turn
    {:ok, result} = Codex.Thread.run(thread, "What is a GenServer in Elixir?")

    # Print the response
    case result.final_response do
      %Codex.Items.AgentMessage{text: text} ->
        IO.puts(text)

      _ ->
        IO.puts("The turn did not produce a final response.")
    end

    # Check token usage
    IO.puts("\nTokens used:")
    IO.puts("  Input: #{result.usage["input_tokens"]}")
    IO.puts("  Output: #{result.usage["output_tokens"]}")
    IO.puts("  Total: #{result.usage["total_tokens"]}")
  end
end
```

### Examining All Items

Access all items produced during a turn.

```elixir
defmodule ItemsExample do
  def explore_items do
    {:ok, thread} = Codex.start_thread()

    {:ok, result} = Codex.Thread.run(
      thread,
      "Explain how Elixir processes work, and give me a simple example"
    )

    # Iterate through completed items in the event stream
    Enum.each(result.events, fn
      %Codex.Events.ItemCompleted{item: %Codex.Items.AgentMessage{text: text}} ->
          IO.puts("\n[Agent Message]")
          IO.puts(text)

      %Codex.Events.ItemCompleted{item: %Codex.Items.Reasoning{text: text}} ->
          IO.puts("\n[Reasoning]")
          IO.puts(text)

      %Codex.Events.ItemCompleted{
        item: %Codex.Items.CommandExecution{command: cmd, exit_code: code, status: status}
      } ->
          IO.puts("\n[Command Execution]")
          IO.puts("Command: #{cmd}")
          IO.puts("Exit Code: #{inspect(code)} (#{status})")

      %Codex.Events.ItemCompleted{item: %Codex.Items.FileChange{changes: changes}} ->
        IO.puts("\n[File Changes]")
        Enum.each(changes, fn %{path: path, kind: kind} ->
          IO.puts("  #{kind}: #{path}")
        end)

      %Codex.Events.ItemCompleted{item: other} ->
        IO.puts("\n[Other Item]")
        IO.inspect(other, label: "item")

      _ ->
        :ok
    end)
  end
end
```

---

## Streaming Responses

### Real-Time Event Processing

Process events as they arrive for responsive UIs.

```elixir
defmodule StreamingExample do
  def stream_response do
    {:ok, thread} = Codex.start_thread()

    {:ok, stream} = Codex.Thread.run_streamed(
      thread,
      "Analyze the files in this directory and suggest improvements"
    )

    # Process events in real-time
    Enum.each(stream, fn event ->
      case event do
        %Codex.Events.ThreadStarted{thread_id: id} ->
          IO.puts("Started thread: #{id}")

        %Codex.Events.TurnStarted{} ->
          IO.puts("Turn started...")

        %Codex.Events.ItemStarted{item: item} ->
          IO.puts("New item: #{item.type}")

        %Codex.Events.ItemUpdated{item: %{type: :command_execution} = cmd} ->
          if cmd.status == :in_progress do
            IO.write(".")  # Progress indicator
          end

        %Codex.Events.ItemCompleted{item: item} ->
          case item do
            %{type: :agent_message, text: text} ->
              IO.puts("\n\n[Response]")
              IO.puts(text)

            %{type: :command_execution, command: cmd, exit_code: 0} ->
              IO.puts("\n✓ Command succeeded: #{cmd}")

            %{type: :file_change, changes: changes} ->
              IO.puts("\n[Files Changed]")
              Enum.each(changes, fn %{path: path, kind: kind} ->
                IO.puts("  #{kind}: #{path}")
              end)

            _ ->
              :ok
          end

        %Codex.Events.TurnCompleted{usage: usage} ->
          IO.puts("\n\nTurn completed!")
          IO.puts("Tokens: #{usage.input_tokens + usage.output_tokens}")

        _ ->
          :ok
      end
    end)
  end
end
```

### Progressive Display

Stream text responses character by character (simulated).

```elixir
defmodule ProgressiveDisplay do
  def display_progressively do
    {:ok, thread} = Codex.start_thread()

    {:ok, stream} = Codex.Thread.run_streamed(
      thread,
      "Write a short story about a robot learning to code"
    )

    # Accumulate text and display progressively
    stream
    |> Stream.filter(fn
      %Codex.Events.ItemCompleted{item: %{type: :agent_message}} -> true
      _ -> false
    end)
    |> Enum.each(fn %{item: %{text: text}} ->
      # Simulate streaming by printing chunks
      text
      |> String.graphemes()
      |> Enum.each(fn char ->
        IO.write(char)
        Process.sleep(10)  # Adjust for desired speed
      end)
    end)

    IO.puts("\n")
  end
end
```

### Live Tooling Stream (Codex CLI)

Run a live streamed turn that shows shell and MCP tool events without requiring an API key (uses your Codex CLI login if present):

```bash
mix run examples/live_tooling_stream.exs "Summarize this repository and run one quick check"
```

The example prints started/updated/completed tool events (including arguments and streamed results) and falls back to the last agent message if the final response isn’t explicitly included in `turn.completed`.

---

## Structured Output

### JSON Schema with Validation

Request structured data conforming to a schema.

```elixir
defmodule StructuredOutputExample do
  def analyze_code_quality do
    schema = %{
      "type" => "object",
      "properties" => %{
        "overall_score" => %{
          "type" => "integer",
          "minimum" => 0,
          "maximum" => 100
        },
        "issues" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "severity" => %{
                "type" => "string",
                "enum" => ["low", "medium", "high"]
              },
              "description" => %{"type" => "string"},
              "file" => %{"type" => "string"},
              "line" => %{"type" => "integer"}
            },
            "required" => ["severity", "description"]
          }
        },
        "suggestions" => %{
          "type" => "array",
          "items" => %{"type" => "string"}
        }
      },
      "required" => ["overall_score", "issues", "suggestions"]
    }

    {:ok, thread} = Codex.start_thread()

    turn_opts = %Codex.Turn.Options{output_schema: schema}

    {:ok, result} = Codex.Thread.run(
      thread,
      "Analyze the code quality of this Elixir project",
      turn_opts
    )

    case Codex.Turn.Result.json(result) do
      {:ok, data} ->
        IO.puts("Overall Score: #{data["overall_score"]}/100")

        IO.puts("\nIssues Found:")
        Enum.each(data["issues"], fn issue ->
          severity = String.upcase(issue["severity"])
          IO.puts("  [#{severity}] #{issue["description"]}")
          if issue["file"] do
            IO.puts("    File: #{issue["file"]}:#{issue["line"]}")
          end
        end)

        IO.puts("\nSuggestions:")
        Enum.each(data["suggestions"], fn suggestion ->
          IO.puts("  - #{suggestion}")
        end)

      {:error, _} ->
        IO.puts("Failed to parse structured response")
    end
  end
end
```

`result.final_response.parsed` contains the decoded payload whenever the response matches
the requested schema. `Codex.Turn.Result.json/1` returns the same data alongside helpful
error metadata.

### Using with TypedStruct

Define Elixir structs that match your schema.

```elixir
defmodule MyApp.CodeAnalysis do
  use TypedStruct

  typedstruct do
    field :overall_score, integer(), enforce: true
    field :issues, [issue()], default: []
    field :suggestions, [String.t()], default: []
  end

  typedstruct module: Issue do
    field :severity, String.t(), enforce: true
    field :description, String.t(), enforce: true
    field :file, String.t()
    field :line, integer()
  end

  def schema do
    %{
      "type" => "object",
      "properties" => %{
        "overall_score" => %{"type" => "integer", "minimum" => 0, "maximum" => 100},
        "issues" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "severity" => %{"type" => "string", "enum" => ["low", "medium", "high"]},
              "description" => %{"type" => "string"},
              "file" => %{"type" => "string"},
              "line" => %{"type" => "integer"}
            },
            "required" => ["severity", "description"]
          }
        },
        "suggestions" => %{"type" => "array", "items" => %{"type" => "string"}}
      },
      "required" => ["overall_score", "issues", "suggestions"]
    }
  end

  def from_map(%{} = data) do
    issues = parse_issues(data["issues"])

    {:ok, %__MODULE__{
      overall_score: data["overall_score"],
      issues: issues,
      suggestions: data["suggestions"] || []
    }}
  end

  defp parse_issues(issues) when is_list(issues) do
    Enum.map(issues, fn issue ->
      %Issue{
        severity: issue["severity"],
        description: issue["description"],
        file: issue["file"],
        line: issue["line"]
      }
    end)
  end
end

# Usage
{:ok, thread} = Codex.start_thread()
turn_opts = %Codex.Turn.Options{output_schema: MyApp.CodeAnalysis.schema()}
{:ok, result} = Codex.Thread.run(thread, "Analyze code", turn_opts)

case {result.final_response, Codex.Turn.Result.json(result)} do
  {%Codex.Items.AgentMessage{parsed: parsed}, {:ok, parsed}} ->
    {:ok, analysis} = MyApp.CodeAnalysis.from_map(parsed)
    IO.puts("Score: #{analysis.overall_score}")

  {_, {:error, reason}} ->
    IO.inspect(reason, label: "structured output error")
end
```

---

## Multi-Turn Conversations

### Context Retention

Maintain context across multiple turns.

```elixir
defmodule ConversationExample do
  def multi_turn_conversation do
    {:ok, thread} = Codex.start_thread()

    # Turn 1: Provide context
    {:ok, result1} = Codex.Thread.run(
      thread,
      "I have a bug in my GenServer. It crashes when I send it a {:stop, reason} message."
    )

    IO.puts("Agent: #{render(result1.final_response)}")

    # Turn 2: Ask follow-up (agent remembers previous context)
    {:ok, result2} = Codex.Thread.run(
      thread,
      "Can you show me an example of how to handle that message correctly?"
    )

    IO.puts("\nAgent: #{render(result2.final_response)}")

    # Turn 3: More specific
    {:ok, result3} = Codex.Thread.run(
      thread,
      "What if I want to perform cleanup before stopping?"
    )

    IO.puts("\nAgent: #{render(result3.final_response)}")

    # Save thread_id for later
    IO.puts("\nThread ID: #{thread.thread_id}")
  end

  defp render(%Codex.Items.AgentMessage{text: text}), do: text
  defp render(_), do: "(no response produced)"
end
```

### Resuming Sessions

Resume a previous conversation.

```elixir
defmodule ResumeExample do
  def resume_previous_session(thread_id) do
    # Resume the thread
    {:ok, thread} = Codex.resume_thread(thread_id)

    # Continue the conversation
    {:ok, result} = Codex.Thread.run(
      thread,
      "Can you remind me what we were discussing?"
    )

    IO.puts(render(result.final_response))
  end

  def save_and_resume do
    # Start thread and have conversation
    {:ok, thread} = Codex.start_thread()

    {:ok, result1} = Codex.Thread.run(thread, "Remember the number 42")
    IO.puts(render(result1.final_response))

    # Save thread_id (e.g., to database, file, etc.)
    thread_id = thread.thread_id
    File.write!("thread_id.txt", thread_id)

    # Simulate restart: read thread_id and resume
    saved_id = File.read!("thread_id.txt")
    {:ok, resumed_thread} = Codex.resume_thread(saved_id)

    {:ok, result2} = Codex.Thread.run(resumed_thread, "What number should I remember?")
    IO.puts("\nAfter resuming: #{render(result2.final_response)}")
  end

  defp render(%Codex.Items.AgentMessage{text: text}), do: text
  defp render(_), do: "(no response produced)"
end
```

### Agent Runner Loop

Automatically follow continuation tokens with the multi-turn runner.

```elixir
defmodule AgentRunnerExample do
  def run do
    {:ok, thread} = Codex.start_thread()

    Codex.AgentRunner.run(thread, "Plan a checklist",
      agent: %{instructions: "Keep responses short"},
      run_config: %{max_turns: 3}
    )
  end
end
```

Run `mix run examples/agent_runner_multi_turn.exs` for a runnable script.

---

## File Operations

### Tracking File Changes

Monitor file modifications made by the agent.

```elixir
defmodule FileOperationsExample do
  def track_file_changes do
    {:ok, thread} = Codex.start_thread()

    {:ok, stream} = Codex.Thread.run_streamed(
      thread,
      "Add comprehensive documentation to all modules in lib/"
    )

    # Track changes
    changes = stream
      |> Stream.filter(fn
        %Codex.Events.ItemCompleted{item: %{type: :file_change}} -> true
        _ -> false
      end)
      |> Enum.map(fn %{item: file_change} ->
        Enum.map(file_change.changes, fn change ->
          {change.kind, change.path}
        end)
      end)
      |> List.flatten()

    # Summarize
    IO.puts("File Changes:")
    changes
    |> Enum.group_by(fn {kind, _} -> kind end)
    |> Enum.each(fn {kind, files} ->
      IO.puts("\n#{String.upcase(to_string(kind))}:")
      Enum.each(files, fn {_, path} ->
        IO.puts("  - #{path}")
      end)
    end)
  end

  def review_before_apply do
    {:ok, thread} = Codex.start_thread()

    {:ok, result} = Codex.Thread.run(
      thread,
      "Refactor the authentication module"
    )

    # Extract file changes
    file_changes = result.items
      |> Enum.filter(fn
        %{type: :file_change} -> true
        _ -> false
      end)

    # Review each change
    Enum.each(file_changes, fn change ->
      IO.puts("\nProposed Changes:")
      Enum.each(change.changes, fn %{path: path, kind: kind} ->
        IO.puts("  #{kind}: #{path}")

        # Could display diffs here
        if kind == :update do
          # Read current file and show diff
          # (Would need access to diff from codex-rs)
        end
      end)

      # Prompt user
      IO.puts("\nApply these changes? (y/n)")
      response = IO.gets("")

      if String.trim(response) == "y" do
        IO.puts("Changes applied (by codex-rs)")
      else
        IO.puts("Changes rejected - would need to revert")
      end
    end)
  end
end
```

---

## Command Execution

### Monitoring Commands

Track commands executed by the agent.

```elixir
defmodule CommandExample do
  def monitor_commands do
    {:ok, thread} = Codex.start_thread()

    {:ok, stream} = Codex.Thread.run_streamed(
      thread,
      "List the top-level files and print the working directory"
    )

    # Collect all commands
    commands = stream
      |> Stream.filter(fn
        %Codex.Events.ItemCompleted{item: %{type: :command_execution}} -> true
        _ -> false
      end)
      |> Enum.map(fn %{item: cmd} -> cmd end)

    # Display results
    IO.puts("Commands Executed:")
    Enum.each(commands, fn cmd ->
      status_icon = case cmd.status do
        :completed when cmd.exit_code == 0 -> "✓"
        :completed -> "✗"
        :failed -> "✗"
        _ -> "?"
      end

      IO.puts("\n#{status_icon} #{cmd.command}")
      IO.puts("  Exit Code: #{cmd.exit_code || "N/A"}")

      if cmd.aggregated_output != "" do
        IO.puts("  Output:")
        cmd.aggregated_output
        |> String.split("\n")
        |> Enum.take(5)  # First 5 lines
        |> Enum.each(fn line ->
          IO.puts("    #{line}")
        end)
      end
    end)
  end

end
```

---

## Error Handling

### Graceful Error Recovery

Handle errors gracefully in production.

```elixir
defmodule ErrorHandlingExample do
  require Logger

  def robust_turn(thread, input, opts \\ %Codex.Turn.Options{}) do
    case Codex.Thread.run(thread, input, opts) do
      {:ok, result} ->
        {:ok, result}

      {:error, {:turn_failed, error}} ->
        Logger.error("Turn failed: #{error.message}")
        handle_turn_failure(error)

      {:error, {:process, reason}} ->
        Logger.error("Process error: #{inspect(reason)}")
        {:error, :process_error}

      {:error, {:config, reason}} ->
        Logger.error("Configuration error: #{inspect(reason)}")
        {:error, :config_error}

      {:error, reason} ->
        Logger.error("Unknown error: #{inspect(reason)}")
        {:error, :unknown}
    end
  end

  defp handle_turn_failure(error) do
    # Could implement retry logic, fallback, etc.
    if retryable?(error) do
      Logger.info("Error is retryable, consider retry logic")
    end

    {:error, :turn_failed}
  end

  defp retryable?(error) do
    # Check if error message indicates transient issue
    error.message =~ ~r/(rate limit|timeout|temporarily unavailable)/i
  end

  def with_retry(thread, input, max_attempts \\ 3) do
    do_with_retry(thread, input, max_attempts, 1)
  end

  defp do_with_retry(thread, input, max_attempts, attempt) do
    case Codex.Thread.run(thread, input) do
      {:ok, result} ->
        {:ok, result}

      {:error, {:turn_failed, error}} when attempt < max_attempts ->
        if retryable?(error) do
          Logger.info("Retry attempt #{attempt + 1}/#{max_attempts}")
          # Exponential backoff
          Process.sleep(1000 * :math.pow(2, attempt - 1) |> round())
          do_with_retry(thread, input, max_attempts, attempt + 1)
        else
          {:error, {:turn_failed, error}}
        end

      error ->
        error
    end
  end
end
```

### Validation and Sanitization

Validate inputs and outputs.

```elixir
defmodule ValidationExample do
  def safe_run(thread, input) do
    with :ok <- validate_input(input),
         {:ok, result} <- Codex.Thread.run(thread, input),
         :ok <- validate_result(result) do
      {:ok, result}
    end
  end

  defp validate_input(input) do
    cond do
      !is_binary(input) ->
        {:error, :input_must_be_string}

      String.length(input) == 0 ->
        {:error, :input_cannot_be_empty}

      String.length(input) > 100_000 ->
        {:error, :input_too_long}

      true ->
        :ok
    end
  end

  defp validate_result(result) do
    cond do
      !result.usage ->
        {:error, :missing_usage}

      result.usage.input_tokens + result.usage.output_tokens == 0 ->
        {:error, :no_tokens_used}

      true ->
        :ok
    end
  end
end
```

---

## Configuration

### Environment-Based Configuration

Configure based on environment.

The default model is `gpt-5.3-codex` (unless overridden by `CODEX_MODEL`, `OPENAI_DEFAULT_MODEL`, or `CODEX_MODEL_DEFAULT`) and remote model metadata is gated behind `features.remote_models = true` in the effective Codex config (system `/etc/codex/config.toml`, user `$CODEX_HOME/config.toml`, and `.codex/config.toml` layers between `cwd` and the project root; root markers default to `.git` and are configurable via `project_root_markers`). When enabled, the SDK merges the remote `/models` list (or bundled `models.json`) with local presets.

```elixir
defmodule MyApp.Codex do
  def start_thread do
    codex_opts = %Codex.Options{
      api_key: api_key(),
      base_url: base_url(),
      codex_path_override: codex_path()
    }

    thread_opts = %Codex.Thread.Options{
      model: model(),
      sandbox_mode: sandbox_mode(),
      working_directory: working_directory()
    }

    Codex.start_thread(codex_opts, thread_opts)
  end

  defp api_key do
    System.get_env("CODEX_API_KEY") ||
      Application.get_env(:my_app, :codex_api_key)
  end

  defp base_url do
    Application.get_env(:my_app, :codex_base_url)
  end

  defp codex_path do
    Application.get_env(:my_app, :codex_path)
  end

  defp model do
    Application.get_env(:my_app, :codex_model, "o1")
  end

  defp sandbox_mode do
    case Mix.env() do
      :prod -> :read_only
      _ -> :workspace_write
    end
  end

  defp working_directory do
    File.cwd!()
  end
end
```

### Per-Request Configuration

Override configuration per request.

```elixir
defmodule ConfigExample do
  def analyze_with_different_models(input) do
    models = ["gpt-4", "o1", "gpt-4-turbo"]

    results = Enum.map(models, fn model ->
      thread_opts = %Codex.Thread.Options{model: model}
      {:ok, thread} = Codex.start_thread(%Codex.Options{}, thread_opts)

      {:ok, result} = Codex.Thread.run(thread, input)

      {model, result}
    end)

    # Compare results
    Enum.each(results, fn {model, result} ->
      IO.puts("\n#{model}:")
      IO.puts(String.slice(result.final_response, 0..200))
      IO.puts("Tokens: #{result.usage.input_tokens + result.usage.output_tokens}")
    end)
  end
end
```

You can also pass CLI config overrides and shell environment policy entries via thread options:

```elixir
{:ok, thread_opts} =
  Codex.Thread.Options.new(
    model_provider: "mistral",
    base_instructions: "Keep answers brief.",
    shell_environment_policy: %{
      inherit: "core",
      exclude: ["AWS_*"]
    },
    config_overrides: %{
      "model_reasoning_summary" => "concise"
    }
  )

{:ok, thread} = Codex.start_thread(%Codex.Options{}, thread_opts)
```

---

## Advanced Patterns

### Concurrent Turns

Execute multiple turns concurrently.

```elixir
defmodule ConcurrentExample do
  def parallel_analysis(files) do
    tasks = Enum.map(files, fn file ->
      Task.async(fn ->
        {:ok, thread} = Codex.start_thread()
        {:ok, result} = Codex.Thread.run(thread, "Analyze #{file}")
        {file, result}
      end)
    end)

    results = Task.await_many(tasks, 60_000)

    Enum.each(results, fn {file, result} ->
      preview =
        case result.final_response do
          %Codex.Items.AgentMessage{text: text} -> String.slice(text, 0..200)
          _ -> "(no response produced)"
        end

      IO.puts("\n#{file}:")
      IO.puts(preview)
    end)
  end

  def map_reduce_pattern(items) do
    # Map: Process each item concurrently
    tasks = Enum.map(items, fn item ->
      Task.async(fn ->
        {:ok, thread} = Codex.start_thread()
        {:ok, result} = Codex.Thread.run(thread, "Process #{item}")

        case result.final_response do
          %Codex.Items.AgentMessage{text: text} -> text
          _ -> ""
        end
      end)
    end)

    responses = Task.await_many(tasks, 60_000)

    # Reduce: Combine results
    {:ok, thread} = Codex.start_thread()

    summary_prompt = """
    Summarize these analyses:

    #{Enum.join(responses, "\n\n---\n\n")}
    """

    {:ok, result} = Codex.Thread.run(thread, summary_prompt)

    case result.final_response do
      %Codex.Items.AgentMessage{text: text} ->
        IO.puts("Summary:")
        IO.puts(text)

      _ ->
        IO.puts("Summary not available")
    end
  end
end
```

### Agent Collaboration

Multiple agents working together.

```elixir
defmodule CollaborationExample do
  def collaborative_code_review(file) do
    # Analyzer agent
    {:ok, analyzer} = Codex.start_thread()
    {:ok, analysis} = Codex.Thread.run(
      analyzer,
      "Analyze #{file} for potential issues"
    )

    # Security expert agent
    {:ok, security} = Codex.start_thread()
    {:ok, security_review} = Codex.Thread.run(
      security,
      """
      Review this code for security issues:

      Analysis: #{analysis.final_response.text}
      """
    )

    # Performance expert agent
    {:ok, performance} = Codex.start_thread()
    {:ok, perf_review} = Codex.Thread.run(
      performance,
      """
      Review this code for performance issues:

      Analysis: #{analysis.final_response.text}
      """
    )

    # Synthesizer agent
    {:ok, synthesizer} = Codex.start_thread()

    synthesis_prompt = """
    Synthesize these reviews into actionable recommendations:

    Security Review:
    #{security_review.final_response.text}

    Performance Review:
    #{perf_review.final_response.text}
    """

    {:ok, final} = Codex.Thread.run(synthesizer, synthesis_prompt)

    case final.final_response do
      %Codex.Items.AgentMessage{text: text} ->
        IO.puts("Final Recommendations:")
        IO.puts(text)

      _ ->
        IO.puts("No recommendations produced.")
    end
  end
end
```

### Tool Output Bridging and Auto-Run (Transport Notes)

The SDK includes a tool registry and can collect structured tool outputs during auto-run cycles.
However, the default transport (`codex exec --json`) does not currently expose a
supported mechanism to inject tool outputs back into the CLI. Treat the example below as a
conceptual demo until a tool-capable transport (e.g. MCP-hosted tools or protocol/app-server) is
adopted.

```elixir
defmodule ToolBridgingExample do
  def run_with_registered_tool do
    defmodule MathTool do
      use Codex.Tool, name: "math_tool", description: "adds two numbers"

      @impl true
      def invoke(%{"x" => x, "y" => y}, _context), do: {:ok, %{"sum" => x + y}}
    end

    {:ok, _handle} = Codex.Tools.register(MathTool)

    {:ok, thread} =
      Codex.start_thread(approval_policy: Codex.Approvals.StaticPolicy.allow())

    {:ok, result} =
      Codex.Thread.run_auto(thread, "Ask the math tool to add 4 and 5", max_attempts: 2)

    IO.inspect(result.raw[:tool_outputs], label: "tool outputs captured by SDK")
    IO.inspect(result.thread.pending_tool_outputs, label: "pending outputs after turn")
  end
end
```

### Streaming with State Accumulation

Build up state while streaming.

```elixir
defmodule StatefulStreamingExample do
  def accumulate_state do
    {:ok, thread} = Codex.start_thread()
    {:ok, stream} = Codex.Thread.run_streamed(thread, "Implement a new feature")

    final_state = Enum.reduce(stream, initial_state(), fn event, state ->
      case event do
        %Codex.Events.ThreadStarted{thread_id: id} ->
          %{state | thread_id: id}

        %Codex.Events.ItemCompleted{item: %Codex.Items.CommandExecution{} = cmd} ->
          %{state | commands: [cmd | state.commands]}

        %Codex.Events.ItemCompleted{item: %Codex.Items.FileChange{} = file} ->
          %{state | files: [file | state.files]}

        %Codex.Events.ItemCompleted{item: %Codex.Items.AgentMessage{text: text}} ->
          %{state | messages: [text | state.messages]}

        %Codex.Events.TurnCompleted{usage: usage} when is_map(usage) ->
          %{state | usage: usage}

        _ ->
          state
      end
    end)

    display_summary(final_state)
  end

  defp initial_state do
    %{
      thread_id: nil,
      commands: [],
      files: [],
      messages: [],
      usage: nil
    }
  end

  defp display_summary(state) do
    IO.puts("Turn Summary:")
    IO.puts("  Thread ID: #{state.thread_id}")
    IO.puts("  Commands: #{length(state.commands)}")
    IO.puts("  Files Changed: #{count_file_changes(state.files)}")
    IO.puts("  Messages: #{length(state.messages)}")

    if state.usage do
      IO.puts("  Tokens: #{state.usage.input_tokens + state.usage.output_tokens}")
    end
  end

  defp count_file_changes(files) do
    files
    |> Enum.flat_map(fn file -> file.changes end)
    |> length()
  end
end
```

---

## Production Patterns

### Telemetry Integration

Monitor SDK usage in production.

```elixir
defmodule MyApp.TelemetryHandler do
  require Logger

  def setup do
    :telemetry.attach_many(
      "my-app-codex-handler",
      [
        [:codex, :turn, :start],
        [:codex, :turn, :stop],
        [:codex, :turn, :exception]
      ],
      &handle_event/4,
      nil
    )
  end

  def handle_event([:codex, :turn, :start], measurements, metadata, _config) do
    Logger.info("Codex turn started", thread_id: metadata.thread_id)

    # Could send to metrics system
    :telemetry.execute(
      [:my_app, :codex, :turn, :count],
      %{count: 1},
      metadata
    )
  end

  def handle_event([:codex, :turn, :stop], measurements, metadata, _config) do
    Logger.info("Codex turn completed",
      thread_id: metadata.thread_id,
      duration_ms: measurements.duration / 1_000_000,
      tokens: metadata.usage.input_tokens + metadata.usage.output_tokens
    )

    # Send metrics
    :telemetry.execute(
      [:my_app, :codex, :turn, :duration],
      %{duration: measurements.duration},
      metadata
    )

    :telemetry.execute(
      [:my_app, :codex, :tokens],
      %{
        input: metadata.usage.input_tokens,
        output: metadata.usage.output_tokens,
        total: metadata.usage.input_tokens + metadata.usage.output_tokens
      },
      metadata
    )
  end

  def handle_event([:codex, :turn, :exception], measurements, metadata, _config) do
    Logger.error("Codex turn failed",
      thread_id: metadata.thread_id,
      error: metadata.error,
      duration_ms: measurements.duration / 1_000_000
    )

    # Alert on failures
    :telemetry.execute(
      [:my_app, :codex, :turn, :error],
      %{count: 1},
      metadata
    )
  end
end

# In application.ex
def start(_type, _args) do
  MyApp.TelemetryHandler.setup()
  # ... rest of supervision tree
end
```

### Rate Limiting

Implement rate limiting for API calls.

```elixir
defmodule MyApp.RateLimiter do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def acquire do
    GenServer.call(__MODULE__, :acquire)
  end

  @impl true
  def init(_) do
    state = %{
      tokens: 10,
      last_refill: System.monotonic_time(:second)
    }

    schedule_refill()
    {:ok, state}
  end

  @impl true
  def handle_call(:acquire, _from, state) do
    state = refill_tokens(state)

    if state.tokens > 0 do
      {:reply, :ok, %{state | tokens: state.tokens - 1}}
    else
      {:reply, {:error, :rate_limited}, state}
    end
  end

  @impl true
  def handle_info(:refill, state) do
    schedule_refill()
    {:noreply, %{state | tokens: 10}}
  end

  defp refill_tokens(state) do
    now = System.monotonic_time(:second)
    elapsed = now - state.last_refill

    if elapsed >= 60 do
      %{state | tokens: 10, last_refill: now}
    else
      state
    end
  end

  defp schedule_refill do
    Process.send_after(self(), :refill, 60_000)
  end
end

# Usage
defmodule MyApp.Codex do
  def run(thread, input) do
    case MyApp.RateLimiter.acquire() do
      :ok ->
        Codex.Thread.run(thread, input)

      {:error, :rate_limited} ->
        {:error, :rate_limited}
    end
  end
end
```

### Supervised Turn Execution

Run turns under supervision.

```elixir
defmodule MyApp.TurnSupervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {Task.Supervisor, name: MyApp.TurnTaskSupervisor}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def run_supervised(thread, input, opts \\ %{}) do
    Task.Supervisor.async(MyApp.TurnTaskSupervisor, fn ->
      Codex.Thread.run(thread, input, opts)
    end)
    |> Task.await()
  end
end
```

---

## Live Usage & Compaction

`examples/live_usage_and_compaction.exs` runs against the live Codex backend (requires `CODEX_API_KEY` or a CLI login) and mirrors the latest defaults:

- Uses the SDK default model (`gpt-5.3-codex`) and reasoning effort.
- Streams events, printing token-usage deltas and turn diffs as they arrive.
- Captures explicit compaction notifications (including usage deltas) and merges them into the displayed token totals.
- Prints the final agent response alongside merged usage.

Run it with:

```bash
mix run examples/live_usage_and_compaction.exs "summarize recent changes"
```

Note: `examples/run_all.sh` exports `CODEX_MODEL=gpt-5.3-codex` by default, and `examples/conversation_and_resume.exs`, `examples/live_session_walkthrough.exs`, and `examples/live_mcp_and_sessions.exs` also explicitly set `model: "gpt-5.3-codex"`. Update those scripts if you want a different model.

## Live Exec Controls

`examples/live_exec_controls.exs` streams against the live Codex CLI while forwarding per-turn env,
cancellation tokens, and custom timeouts to `codex exec`. Use it to validate env injection for
tooling or to wire cancellation tokens from upstream request lifecycles.

```bash
mix run examples/live_exec_controls.exs \
  "List three repo files and echo \$CODEX_DEMO_ENV"
```

Events with `requires_approval: false` bypass approval hooks automatically; only flagged operations
invoke your configured approval policy or hook.

Overrides remain available:

```bash
# Custom env, timeout, and cancellation token
mix run examples/live_exec_controls.exs \
  "List three repo files and echo \$CODEX_DEMO_ENV" \
  --env CODEX_DEMO_ENV=from-docs \
  --timeout-ms 45000 \
  --cancel demo-token-123
```

If your Codex CLI is older and does not yet support `--cancellation-token`, rerun without
`--cancel` or upgrade via `npm install -g @openai/codex`.

## Live Telemetry Stream

`examples/live_telemetry_stream.exs` attaches telemetry handlers to the live Codex CLI so you can observe thread/turn identifiers, source metadata, token-usage deltas, diff updates, and compaction savings as they stream in. It uses a low reasoning effort and a short default prompt to return quickly.

```bash
mix run examples/live_telemetry_stream.exs
```

Auth falls back to your Codex CLI login when `CODEX_API_KEY` is not set.

## Additional Live Examples

- `examples/live_collaboration_modes.exs` — lists collaboration presets and runs a turn
- `examples/live_personality.exs` — compares friendly, pragmatic, and none personality overrides
- `examples/live_config_overrides.exs` — nested config override auto-flattening (thread and turn level)
- `examples/live_thread_management.exs` — demonstrates thread read/fork/rollback/loaded list
- `examples/live_web_search_modes.exs` — toggles web search modes and reports web search items
- `examples/live_rate_limits.exs` — prints rate limit snapshots from token usage events

## App-server Transport

App-server (`codex app-server`) is a **stateful, bidirectional** transport that unlocks upstream v2 APIs (threads list/archive, skills/models/config, server-driven approvals, etc.).

See `guides/05-app-server-transport.md` for the complete guide, and run the live scripts:

```bash
mix run examples/live_app_server_basic.exs
mix run examples/live_app_server_streaming.exs "Reply with exactly ok and nothing else."
mix run examples/live_app_server_approvals.exs
mix run examples/live_collaboration_modes.exs
mix run examples/live_personality.exs
mix run examples/live_thread_management.exs
```

Minimal usage with existing thread APIs:

```elixir
{:ok, codex_opts} = Codex.Options.new(%{})
{:ok, conn} = Codex.AppServer.connect(codex_opts)

{:ok, thread} =
  Codex.start_thread(codex_opts, %{
    transport: {:app_server, conn},
    working_directory: File.cwd!()
  })

{:ok, result} = Codex.Thread.run(thread, "List the available skills for this repo")
IO.inspect(result.final_response, label: "final_response")
```

### Custom prompts and skills helpers

```elixir
{:ok, prompts} = Codex.Prompts.list()
{:ok, expanded} = Codex.Prompts.expand(Enum.at(prompts, 0), "FILE=lib/app.ex")

{:ok, %{"data" => skills}} = Codex.Skills.list(conn, skills_enabled: true)
first_skill = skills |> List.first() |> Map.get("skills") |> List.first()
{:ok, skill_body} = Codex.Skills.load(first_skill, skills_enabled: true)
```

## Realtime Voice Interactions

### Basic Realtime Session

Set up a bidirectional voice session using the OpenAI Realtime API:

```elixir
defmodule RealtimeExample do
  alias Codex.Realtime
  alias Codex.Realtime.Config.{RunConfig, SessionModelSettings, TurnDetectionConfig}

  def start_session do
    # Create a realtime agent
    agent = Realtime.agent(
      name: "VoiceAssistant",
      instructions: "You are a helpful voice assistant."
    )

    # Configure session with voice and turn detection
    config = %RunConfig{
      model_settings: %SessionModelSettings{
        voice: "alloy",
        turn_detection: %TurnDetectionConfig{
          type: :semantic_vad,
          eagerness: :medium
        }
      }
    }

    # Start the session
    {:ok, session} = Realtime.start_session(agent, config)

    # Subscribe to events
    Realtime.subscribe(session, self())

    # Session is now ready for audio
    session
  end

  def handle_events do
    receive do
      {:realtime_event, %Codex.Realtime.Events.RealtimeAudioEvent{} = event} ->
        # Handle audio from the agent
        play_audio(event.audio)
        handle_events()

      {:realtime_event, %Codex.Realtime.Events.RealtimeAgentStateEvent{state: state}} ->
        IO.puts("Agent state: #{state}")
        handle_events()

      {:realtime_event, event} ->
        IO.inspect(event, label: "Event")
        handle_events()
    after
      30_000 -> :timeout
    end
  end
end
```

### Realtime with Function Tools

Add function calling capabilities to realtime agents:

```elixir
defmodule RealtimeToolsExample do
  alias Codex.Realtime

  def create_agent_with_tools do
    Realtime.agent(
      name: "WeatherAssistant",
      instructions: "Help users check the weather.",
      tools: [
        %{
          name: "get_weather",
          description: "Get weather for a location",
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
  end
end
```

### Multi-Agent Handoffs

Hand off conversations between specialized agents:

```elixir
defmodule RealtimeHandoffsExample do
  alias Codex.Realtime

  def create_agents do
    greeter = Realtime.agent(
      name: "Greeter",
      instructions: "Greet users and hand off to specialists."
    )

    specialist = Realtime.agent(
      name: "TechSupport",
      instructions: "Provide technical assistance."
    )

    # Configure greeter to hand off to specialist
    greeter_with_handoff = Realtime.add_handoff(greeter, specialist,
      condition: "When user needs technical help"
    )

    {greeter_with_handoff, specialist}
  end
end
```

Run realtime examples:
```bash
export CODEX_API_KEY=your-key
# or export OPENAI_API_KEY=your-key
mix run examples/realtime_basic.exs
mix run examples/realtime_tools.exs
mix run examples/realtime_handoffs.exs
mix run examples/live_realtime_voice.exs
```

## Voice Pipeline

### Basic STT -> Workflow -> TTS Pipeline

Process audio through speech-to-text, custom workflow, and text-to-speech:

```elixir
defmodule VoicePipelineExample do
  alias Codex.Voice.{Pipeline, SimpleWorkflow, Config}
  alias Codex.Voice.Config.TTSSettings
  alias Codex.Voice.Input.AudioInput

  def run_pipeline(audio_data) do
    # Create a simple workflow
    workflow = SimpleWorkflow.new(
      fn transcribed_text ->
        # Process the transcribed text
        response = "I heard you say: #{transcribed_text}"
        [response]
      end,
      greeting: "Hello! How can I help you?"
    )

    # Configure the pipeline
    config = %Config{
      workflow_name: "SimpleVoice",
      tts_settings: %TTSSettings{voice: :nova}
    }

    # Create and start the pipeline
    {:ok, pipeline} = Pipeline.start_link(workflow: workflow, config: config)

    # Create audio input
    input = AudioInput.new(audio_data, format: :wav)

    # Run the pipeline
    {:ok, result} = Pipeline.run(pipeline, input)

    # Collect audio output
    result
    |> Enum.filter(fn
      %Codex.Voice.Events.VoiceStreamEventAudio{} -> true
      _ -> false
    end)
    |> Enum.map(& &1.data)
    |> IO.iodata_to_binary()
  end
end
```

### Multi-Turn Voice Conversations

Maintain conversation context across multiple turns:

```elixir
defmodule VoiceMultiTurnExample do
  alias Codex.Voice.{Pipeline, AgentWorkflow, Config}
  alias Codex.Voice.Input.StreamedAudioInput

  def create_conversational_pipeline do
    # Use AgentWorkflow for multi-turn conversations
    workflow = AgentWorkflow.new(
      agent: %{
        instructions: "You are a helpful assistant. Remember context from earlier in the conversation."
      }
    )

    config = %Config{
      workflow_name: "ConversationalAssistant",
      tts_settings: %Config.TTSSettings{voice: :alloy}
    }

    {:ok, pipeline} = Pipeline.start_link(
      workflow: workflow,
      config: config
    )

    pipeline
  end

  def stream_conversation(pipeline, audio_stream) do
    # Create streaming input
    input = StreamedAudioInput.new()

    # Start processing
    {:ok, result_stream} = Pipeline.run_streamed(pipeline, input)

    # Feed audio chunks
    Task.start(fn ->
      for chunk <- audio_stream do
        StreamedAudioInput.push(input, chunk)
      end
      StreamedAudioInput.close(input)
    end)

    # Process results
    result_stream
  end
end
```

### Voice with Codex Agent

Integrate the voice pipeline with a full Codex agent:

```elixir
defmodule VoiceWithAgentExample do
  alias Codex.Voice.{Pipeline, AgentWorkflow, Config}

  def create_agent_voice_pipeline do
    # Create workflow backed by Codex.Agent
    workflow = AgentWorkflow.new(
      agent: %{
        instructions: """
        You are a coding assistant accessible via voice.
        When asked about code, provide clear explanations.
        """,
        tools: [Codex.Tools.FileSearchTool]
      }
    )

    config = %Config{
      workflow_name: "CodingAssistant",
      stt_settings: %Config.STTSettings{
        model: "gpt-4o-transcribe"
      },
      tts_settings: %Config.TTSSettings{
        voice: :echo,
        model: "gpt-4o-mini-tts"
      }
    }

    Pipeline.start_link(workflow: workflow, config: config)
  end
end
```

Run voice pipeline examples:
```bash
export CODEX_API_KEY=your-key
# or export OPENAI_API_KEY=your-key
mix run examples/voice_pipeline.exs
mix run examples/voice_multi_turn.exs
mix run examples/voice_with_agent.exs
```

## Conclusion

These examples demonstrate the flexibility and power of the Elixir Codex SDK. Key patterns include:

- **Streaming** for responsive UIs
- **Structured output** for data extraction
- **Multi-turn** for complex conversations
- **Error handling** for robustness
- **Concurrent execution** for performance
- **Production patterns** for observability and reliability
- **Realtime voice** for bidirectional audio interactions
- **Voice pipeline** for STT -> Workflow -> TTS processing

Refer to the [API Reference](03-api-reference.md) for complete documentation of all functions and types.
