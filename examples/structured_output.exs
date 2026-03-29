#!/usr/bin/env mix run

Code.require_file(Path.expand("support/example_helper.exs", __DIR__))

alias CodexExamples.Support

Support.init!()

case Support.ensure_local_execution_surface(
       "this example writes host-local output schema files and does not support --ssh-host"
     ) do
  :ok ->
    :ok

  {:skip, reason} ->
    IO.puts("SKIPPED: #{reason}")
    System.halt(0)
end

alias Codex.ExamplesSupport
alias Codex.Turn.Result, as: TurnResult

defmodule Examples.StructuredOutput do
  @moduledoc false

  def run_schema_example do
    if ExamplesSupport.ollama_mode?() do
      IO.puts("Ollama mode detected. Strict output_schema is not reliable in local OSS mode.")

      IO.puts("Running a host-side structured fallback example instead.")
      print_schema_data(fallback_schema_data())
    else
      {:ok, thread} = Codex.start_thread(Support.codex_options!(), Support.thread_opts!())

      case schema_result(thread) do
        {:ok, result} ->
          case schema_data(result) do
            {:ok, data} ->
              print_schema_data(data)

            {:error, reason} ->
              IO.puts("Failed to decode structured output: #{inspect(reason)}")
          end

        {:error, reason} ->
          print_transport_error("Structured output turn failed", reason)
      end
    end
  end

  def run_struct_example do
    if ExamplesSupport.ollama_mode?() do
      IO.puts("Ollama mode detected. Strict output_schema is not reliable in local OSS mode.")

      IO.puts("Running a host-side struct-decoding fallback example instead.")

      with {:ok, summary} <-
             Examples.StructuredOutput.CodeAnalysis.from_map(fallback_schema_data()) do
        IO.puts("Score (0-100): #{summary.overall_score}")
        IO.inspect(summary, label: "parsed struct")
      end
    else
      {:ok, thread} = Codex.start_thread(Support.codex_options!(), Support.thread_opts!())

      case struct_result(thread) do
        {:ok, result} ->
          case schema_data(result) do
            {:ok, parsed} ->
              with {:ok, summary} <- Examples.StructuredOutput.CodeAnalysis.from_map(parsed) do
                IO.puts("Score (0-100): #{summary.overall_score}")
                IO.inspect(summary, label: "parsed struct")
              end

            {:error, reason} ->
              IO.puts("Unable to parse structured data: #{inspect(reason)}")
          end

        {:error, reason} ->
          print_transport_error("Structured struct-decoding turn failed", reason)
      end
    end
  end

  defp schema_result(thread) do
    Codex.Thread.run(
      thread,
      """
      Provide a quick code-quality summary for the Elixir standard library.
      Return overall_score as an integer from 0 to 100, where 100 is best and 0 is worst.
      """,
      %{output_schema: schema()}
    )
  end

  defp struct_result(thread) do
    Codex.Thread.run(
      thread,
      """
      Summarise the top two potential bugs in this test suite.
      Return overall_score as an integer from 0 to 100, where 100 is best and 0 is worst.
      """,
      %{output_schema: schema()}
    )
  end

  defp schema_data(result) do
    TurnResult.json(result)
  end

  defp print_schema_data(data) when is_map(data) do
    IO.puts("Structured output:")
    IO.inspect(data, label: "structured_output")

    issues = data["issues"] || []

    IO.puts("Overall score (0-100): #{data["overall_score"]}")
    IO.puts("\nIssues:")

    if Enum.empty?(issues) do
      IO.puts("  (none reported)")
    else
      Enum.each(issues, fn issue ->
        IO.puts("  [#{String.upcase(issue["severity"])}] #{issue["description"]}")
      end)
    end
  end

  defp fallback_schema_data do
    %{
      "overall_score" => 88,
      "issues" => [
        %{
          "severity" => "medium",
          "description" => "Pattern matching clauses can drift into duplication over time.",
          "file" => "lib/example.ex",
          "line" => 42
        },
        %{
          "severity" => "low",
          "description" => "Tests may miss behavior around error normalization.",
          "file" => "test/example_test.exs",
          "line" => 17
        }
      ],
      "suggestions" => [
        "Consolidate repeated clauses into shared helpers.",
        "Add targeted regression coverage for edge-case failures."
      ]
    }
  end

  defp schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{
        "overall_score" => %{
          "type" => "integer",
          "minimum" => 0,
          "maximum" => 100,
          "description" => "Overall score on a 0-100 scale where 100 is best."
        },
        "issues" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "additionalProperties" => false,
            "properties" => %{
              "severity" => %{"type" => "string", "enum" => ["low", "medium", "high"]},
              "description" => %{"type" => "string"},
              "file" => %{"type" => "string"},
              "line" => %{"type" => "integer"}
            },
            "required" => ["severity", "description", "file", "line"]
          }
        },
        "suggestions" => %{"type" => "array", "items" => %{"type" => "string"}}
      },
      "required" => ["overall_score", "issues", "suggestions"]
    }
  end

  defp print_transport_error(prefix, {:exec_failed, %Codex.Error{} = err}),
    do: print_transport_error(prefix, err)

  defp print_transport_error(prefix, {:turn_failed, %Codex.Error{} = err}),
    do: print_transport_error(prefix, err)

  defp print_transport_error(prefix, %Codex.Error{} = err) do
    IO.puts("#{prefix}: codex failed (#{err.message}).")

    if is_map(err.details) and map_size(err.details) > 0 do
      IO.inspect(err.details, label: "details")
    end
  end

  defp print_transport_error(prefix, %Codex.TransportError{} = err) do
    IO.puts("#{prefix}: codex failed (exit_status=#{err.exit_status}).")

    if is_binary(err.stderr) and err.stderr != "" do
      IO.puts("\nstderr:\n#{err.stderr}")
    end
  end

  defp print_transport_error(prefix, other) do
    IO.puts("#{prefix}: #{inspect(other)}")
  end
end

defmodule Examples.StructuredOutput.CodeAnalysis do
  @moduledoc false

  defstruct overall_score: 0, issues: [], suggestions: []

  defmodule Issue do
    @moduledoc false
    defstruct [:severity, :description, :file, :line]
  end

  @type t :: %__MODULE__{
          overall_score: integer(),
          issues: [Issue.t()],
          suggestions: [String.t()]
        }

  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(%{"overall_score" => score} = data) when is_integer(score) do
    issues =
      data
      |> Map.get("issues", [])
      |> Enum.map(fn issue ->
        struct(Issue, %{
          severity: issue["severity"],
          description: issue["description"],
          file: issue["file"],
          line: issue["line"]
        })
      end)

    {:ok,
     %__MODULE__{
       overall_score: score,
       issues: issues,
       suggestions: Map.get(data, "suggestions", [])
     }}
  end

  def from_map(_other), do: {:error, :invalid_payload}
end

case System.argv() do
  ["struct"] ->
    Examples.StructuredOutput.run_struct_example()

  ["help"] ->
    IO.puts("""
    mix run examples/structured_output.exs [command]

      (no arg)   – run the JSON schema example
      struct     – run the struct decoding example
      help       – show this usage
    """)

  _ ->
    Examples.StructuredOutput.run_schema_example()
end
