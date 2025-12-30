# Prompt 07: FileSearch Hosted Tool Implementation

**Target Version:** 0.4.5
**Date:** 2025-12-30
**Depends On:** None (standalone)

## Objective

Implement a FileSearch hosted tool for searching files using glob patterns and content matching.

## Required Reading

1. **Canonical Implementation:**
   - `codex/codex-rs/core/src/tools/handlers/file_search.rs` - File search handler
   - `codex/codex-rs/core/src/tools/file_searcher.rs` - Search implementation
   - `openai-agents-python/src/agents/tool.py` - Python FileSearchTool

2. **Elixir SDK:**
   - `lib/codex/tools/hosted_tools.ex` - Current structure
   - `lib/codex/tool.ex` - Tool behavior

## Implementation Tasks

### 1. Implement `Codex.Tools.FileSearchTool`

Create `lib/codex/tools/file_search_tool.ex`:

```elixir
defmodule Codex.Tools.FileSearchTool do
  @moduledoc """
  Hosted tool for searching files by name pattern and content.

  ## Options
    * `:base_path` - Base directory for search (default: cwd)
    * `:max_results` - Maximum results to return (default: 100)
    * `:include_hidden` - Include hidden files (default: false)
    * `:case_sensitive` - Case-sensitive matching (default: true)
  """

  @behaviour Codex.Tool

  @impl true
  def metadata do
    %{
      name: "file_search",
      description: "Search for files by name pattern or content",
      schema: %{
        "type" => "object",
        "properties" => %{
          "pattern" => %{
            "type" => "string",
            "description" => "Glob pattern for file names (e.g., '**/*.ex')"
          },
          "content" => %{
            "type" => "string",
            "description" => "Text or regex to search within files (optional)"
          },
          "base_path" => %{
            "type" => "string",
            "description" => "Base directory for search (optional)"
          },
          "max_results" => %{
            "type" => "integer",
            "description" => "Maximum number of results (default: 100)"
          },
          "case_sensitive" => %{
            "type" => "boolean",
            "description" => "Case-sensitive search (default: true)"
          }
        },
        "required" => ["pattern"],
        "additionalProperties" => false
      }
    }
  end

  @impl true
  def invoke(args, context) do
    pattern = Map.fetch!(args, "pattern")
    content = Map.get(args, "content")
    base_path = Map.get(args, "base_path", context[:base_path] || File.cwd!())
    max_results = Map.get(args, "max_results", 100)
    case_sensitive = Map.get(args, "case_sensitive", true)

    with {:ok, files} <- find_files(pattern, base_path),
         {:ok, matched} <- maybe_search_content(files, content, case_sensitive),
         results <- limit_results(matched, max_results) do
      {:ok, format_result(results)}
    end
  end

  defp find_files(pattern, base_path) do
    full_pattern = Path.join(base_path, pattern)

    files =
      full_pattern
      |> Path.wildcard(match_dot: false)
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(&Path.relative_to(&1, base_path))

    {:ok, files}
  rescue
    e -> {:error, {:glob_error, Exception.message(e)}}
  end

  defp maybe_search_content(files, nil, _case_sensitive) do
    {:ok, Enum.map(files, &%{path: &1, matches: nil})}
  end

  defp maybe_search_content(files, content, case_sensitive) do
    regex_opts = if case_sensitive, do: [], else: [:caseless]

    case Regex.compile(content, regex_opts) do
      {:ok, regex} ->
        results =
          files
          |> Enum.map(fn path ->
            matches = search_file(path, regex)
            %{path: path, matches: matches}
          end)
          |> Enum.filter(fn %{matches: m} -> m != [] end)

        {:ok, results}

      {:error, reason} ->
        {:error, {:regex_error, reason}}
    end
  end

  defp search_file(path, regex) do
    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split("\n")
        |> Enum.with_index(1)
        |> Enum.filter(fn {line, _} -> Regex.match?(regex, line) end)
        |> Enum.map(fn {line, num} ->
          %{line_number: num, text: String.trim(line)}
        end)

      {:error, _} ->
        []
    end
  end

  defp limit_results(results, max) do
    Enum.take(results, max)
  end

  defp format_result(results) do
    %{
      "count" => length(results),
      "files" => Enum.map(results, fn r ->
        base = %{"path" => r.path}

        if r.matches do
          Map.put(base, "matches", Enum.map(r.matches, fn m ->
            %{"line" => m.line_number, "text" => m.text}
          end))
        else
          base
        end
      end)
    }
  end
end
```

### 2. Register in HostedTools

Update `lib/codex/tools/hosted_tools.ex`:

```elixir
def file_search(opts \\ []) do
  %{
    module: Codex.Tools.FileSearchTool,
    name: "file_search",
    opts: opts
  }
end

def all do
  [shell(), apply_patch(), file_search(), web_search()]
end
```

## Test Requirements (TDD)

### Unit Tests (`test/codex/tools/file_search_tool_test.exs`)

```elixir
defmodule Codex.Tools.FileSearchToolTest do
  use ExUnit.Case, async: true

  @tmp_dir System.tmp_dir!()

  setup do
    test_dir = Path.join(@tmp_dir, "file_search_test_#{:rand.uniform(100000)}")
    File.mkdir_p!(test_dir)

    # Create test files
    File.write!(Path.join(test_dir, "test.ex"), "defmodule Test do\n  def hello, do: :world\nend")
    File.write!(Path.join(test_dir, "test.exs"), "ExUnit.start()")
    File.mkdir_p!(Path.join(test_dir, "subdir"))
    File.write!(Path.join(test_dir, "subdir/nested.ex"), "# nested file")

    on_exit(fn -> File.rm_rf!(test_dir) end)
    {:ok, test_dir: test_dir}
  end

  describe "metadata/0" do
    test "returns valid tool metadata" do
      meta = Codex.Tools.FileSearchTool.metadata()
      assert meta.name == "file_search"
      assert meta.schema["required"] == ["pattern"]
    end
  end

  describe "invoke/2" do
    test "finds files by glob pattern", %{test_dir: dir} do
      args = %{"pattern" => "*.ex", "base_path" => dir}
      {:ok, result} = Codex.Tools.FileSearchTool.invoke(args, %{})

      assert result["count"] == 1
      assert hd(result["files"])["path"] == "test.ex"
    end

    test "finds files recursively with **", %{test_dir: dir} do
      args = %{"pattern" => "**/*.ex", "base_path" => dir}
      {:ok, result} = Codex.Tools.FileSearchTool.invoke(args, %{})

      assert result["count"] == 2
      paths = Enum.map(result["files"], & &1["path"])
      assert "test.ex" in paths
      assert "subdir/nested.ex" in paths
    end

    test "searches file content", %{test_dir: dir} do
      args = %{"pattern" => "*.ex", "content" => "defmodule", "base_path" => dir}
      {:ok, result} = Codex.Tools.FileSearchTool.invoke(args, %{})

      assert result["count"] == 1
      file = hd(result["files"])
      assert file["path"] == "test.ex"
      assert length(file["matches"]) == 1
      assert hd(file["matches"])["line"] == 1
    end

    test "respects max_results", %{test_dir: dir} do
      args = %{"pattern" => "**/*", "max_results" => 1, "base_path" => dir}
      {:ok, result} = Codex.Tools.FileSearchTool.invoke(args, %{})

      assert result["count"] == 1
    end

    test "case insensitive search", %{test_dir: dir} do
      args = %{
        "pattern" => "*.ex",
        "content" => "DEFMODULE",
        "case_sensitive" => false,
        "base_path" => dir
      }
      {:ok, result} = Codex.Tools.FileSearchTool.invoke(args, %{})

      assert result["count"] == 1
    end

    test "returns empty for no matches", %{test_dir: dir} do
      args = %{"pattern" => "*.rs", "base_path" => dir}
      {:ok, result} = Codex.Tools.FileSearchTool.invoke(args, %{})

      assert result["count"] == 0
      assert result["files"] == []
    end

    test "uses context base_path as default", %{test_dir: dir} do
      args = %{"pattern" => "*.ex"}
      {:ok, result} = Codex.Tools.FileSearchTool.invoke(args, %{base_path: dir})

      assert result["count"] == 1
    end
  end
end
```

### Integration Tests

```elixir
@tag :live
describe "FileSearch tool (live)" do
  test "searches real codebase" do
    Codex.Tools.register(Codex.Tools.FileSearchTool)
    {:ok, result} = Codex.Tools.invoke("file_search", %{"pattern" => "lib/**/*.ex"}, %{})
    assert result["count"] > 0
  end
end
```

## Verification Criteria

1. [ ] All tests pass: `mix test test/codex/tools/file_search_tool_test.exs`
2. [ ] No warnings
3. [ ] No dialyzer errors
4. [ ] No credo issues
5. [ ] Example works: create `examples/file_search_tool.exs`
6. [ ] `examples/run_all.sh` passes

## Update Requirements

### CHANGELOG.md

Add to the existing `## [0.4.5] - 2025-12-30` section:
```markdown
- FileSearch hosted tool with `Codex.Tools.FileSearchTool`
- Glob pattern matching for file discovery
- Content search with regex support
- Case-sensitive/insensitive search modes
```

### Examples

Create `examples/file_search_tool.exs`:
```elixir
# Example: FileSearch Tool Usage
# Run: elixir examples/file_search_tool.exs

Mix.install([{:codex_sdk, path: "."}])

# Register file search tool
{:ok, _} = Codex.Tools.register(Codex.Tools.FileSearchTool)

# Find all Elixir files
{:ok, result} = Codex.Tools.invoke("file_search", %{"pattern" => "lib/**/*.ex"}, %{})
IO.puts("Found #{result["count"]} Elixir files in lib/")

# Search for specific content
{:ok, result} = Codex.Tools.invoke(
  "file_search",
  %{"pattern" => "**/*.ex", "content" => "defmodule"},
  %{}
)
IO.puts("\nFiles containing 'defmodule':")
for file <- result["files"] do
  IO.puts("  #{file["path"]} (#{length(file["matches"])} matches)")
end
```

### README.md

Add FileSearch tool section under Hosted Tools.
