# Example: FileSearch Tool Usage
# Run: mix run examples/file_search_tool.exs
#
# This example demonstrates using the FileSearchTool to search for files
# by glob patterns and optionally filter by content.

Mix.Task.run("app.start")

alias Codex.Tools
alias Codex.Tools.FileSearchTool

IO.puts("""
=== FileSearch Tool Example ===

This example demonstrates the FileSearch hosted tool for searching
local files by glob patterns and content matching.
""")

# Reset and register the file search tool
Tools.reset!()
{:ok, _} = Tools.register(FileSearchTool)

IO.puts("Registered FileSearchTool\n")

# Example 1: Find all Elixir files in lib/
IO.puts("--- Example 1: Find all Elixir files in lib/ ---")

{:ok, result} = Tools.invoke("file_search", %{"pattern" => "lib/**/*.ex"}, %{})
IO.puts("Found #{result["count"]} Elixir files in lib/")

if result["count"] > 0 do
  IO.puts("First 5 files:")

  result["files"]
  |> Enum.take(5)
  |> Enum.each(fn file ->
    IO.puts("  - #{file["path"]}")
  end)
end

IO.puts("")

# Example 2: Find files with specific content
IO.puts("--- Example 2: Search for files containing 'defmodule' ---")

{:ok, result} =
  Tools.invoke(
    "file_search",
    %{"pattern" => "lib/**/*.ex", "content" => "defmodule", "max_results" => 10},
    %{}
  )

IO.puts("Found #{result["count"]} files containing 'defmodule'")

if result["count"] > 0 do
  IO.puts("\nFiles with matches:")

  for file <- Enum.take(result["files"], 5) do
    match_count = length(file["matches"])
    IO.puts("  #{file["path"]} (#{match_count} match#{if match_count > 1, do: "es", else: ""})")

    for match <- Enum.take(file["matches"], 2) do
      IO.puts("    Line #{match["line"]}: #{String.slice(match["text"], 0, 60)}...")
    end
  end
end

IO.puts("")

# Example 3: Case-insensitive search
IO.puts("--- Example 3: Case-insensitive search ---")

{:ok, result} =
  Tools.invoke(
    "file_search",
    %{
      "pattern" => "lib/**/*.ex",
      "content" => "ERROR",
      "case_sensitive" => false,
      "max_results" => 5
    },
    %{}
  )

IO.puts("Found #{result["count"]} files containing 'error' (case-insensitive)")

if result["count"] > 0 do
  for file <- result["files"] do
    IO.puts("  #{file["path"]}")
  end
end

IO.puts("")

# Example 4: Find test files
IO.puts("--- Example 4: Find test files ---")

{:ok, result} = Tools.invoke("file_search", %{"pattern" => "test/**/*_test.exs"}, %{})
IO.puts("Found #{result["count"]} test files")

if result["count"] > 0 do
  IO.puts("First 5 test files:")

  result["files"]
  |> Enum.take(5)
  |> Enum.each(fn file ->
    IO.puts("  - #{file["path"]}")
  end)
end

IO.puts("")

# Example 5: Multiple extensions
IO.puts("--- Example 5: Find Elixir source and script files ---")

{:ok, result} = Tools.invoke("file_search", %{"pattern" => "lib/**/*.{ex,exs}"}, %{})
IO.puts("Found #{result["count"]} .ex and .exs files in lib/")

IO.puts("")

# Example 6: Using with custom base_path
IO.puts("--- Example 6: Search in specific directory ---")

{:ok, result} =
  Tools.invoke("file_search", %{"pattern" => "*.ex", "base_path" => "lib/codex"}, %{})

IO.puts("Found #{result["count"]} .ex files directly in lib/codex/")

if result["count"] > 0 do
  for file <- Enum.take(result["files"], 5) do
    IO.puts("  - #{file["path"]}")
  end
end

IO.puts("")

# Example 7: Search with regex pattern
IO.puts("--- Example 7: Regex content search ---")

{:ok, result} =
  Tools.invoke(
    "file_search",
    %{
      "pattern" => "lib/**/*.ex",
      "content" => "def\\s+\\w+\\(",
      "max_results" => 5
    },
    %{}
  )

IO.puts("Found #{result["count"]} files with function definitions")

if result["count"] > 0 do
  file = hd(result["files"])
  IO.puts("Sample from #{file["path"]}:")

  for match <- Enum.take(file["matches"], 3) do
    IO.puts("  Line #{match["line"]}: #{match["text"]}")
  end
end

IO.puts("\n=== Example Complete ===")
