#!/usr/bin/env mix run

alias Codex.Items
alias Codex.Turn.Result, as: TurnResult

defmodule Examples.StructuredOutput do
  @moduledoc false

  def run_schema_example do
    {:ok, thread} = Codex.start_thread()

    {:ok, result} =
      Codex.Thread.run(
        thread,
        "Provide a quick code-quality summary for the Elixir standard library",
        %{output_schema: schema()}
      )

    case TurnResult.json(result) do
      {:ok, data} ->
        IO.puts("Overall score: #{data["overall_score"]}/100")
        IO.puts("\nIssues:")

        Enum.each(data["issues"], fn issue ->
          IO.puts("  [#{String.upcase(issue["severity"])}] #{issue["description"]}")
        end)

      {:error, reason} ->
        IO.puts("Failed to decode structured output: #{inspect(reason)}")
    end
  end

  def run_struct_example do
    {:ok, thread} = Codex.start_thread()

    {:ok, result} =
      Codex.Thread.run(
        thread,
        "Summarise the top two potential bugs in this test suite",
        %{output_schema: schema()}
      )

    case {result.final_response, TurnResult.json(result)} do
      {%Items.AgentMessage{parsed: parsed}, {:ok, parsed}} ->
        with {:ok, summary} <- Examples.StructuredOutput.CodeAnalysis.from_map(parsed) do
          IO.puts("Score: #{summary.overall_score}")
          IO.inspect(summary, label: "parsed struct")
        end

      {_, {:error, reason}} ->
        IO.puts("Unable to parse structured data: #{inspect(reason)}")
    end
  end

  defp schema do
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
