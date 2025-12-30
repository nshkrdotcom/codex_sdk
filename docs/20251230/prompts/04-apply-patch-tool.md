# Prompt 04: ApplyPatch Hosted Tool Implementation

**Target Version:** 0.4.5
**Date:** 2025-12-30
**Depends On:** None (standalone)

## Objective

Implement the ApplyPatch hosted tool for applying unified diffs to files with approval integration.

## Required Reading

1. **Canonical Implementation:**
   - `codex/codex-rs/core/src/tools/handlers/patch.rs` - Patch handler
   - `codex/codex-rs/protocol/src/approvals.rs` - ApplyPatchApprovalRequest

2. **Elixir SDK:**
   - `lib/codex/tools/hosted_tools.ex` - Current structure
   - `lib/codex/items.ex` - FileChange item type

## Implementation Tasks

### 1. Implement `Codex.Tools.ApplyPatchTool`

Create `lib/codex/tools/apply_patch_tool.ex`:

```elixir
defmodule Codex.Tools.ApplyPatchTool do
  @moduledoc """
  Hosted tool for applying unified diffs to files.

  ## Options
    * `:base_path` - Base directory for file paths
    * `:approval` - Approval callback
    * `:dry_run` - If true, only validate without applying
  """

  @behaviour Codex.Tool

  @impl true
  def metadata do
    %{
      name: "apply_patch",
      description: "Apply a unified diff patch to files",
      schema: %{
        "type" => "object",
        "properties" => %{
          "patch" => %{
            "type" => "string",
            "description" => "The unified diff patch to apply"
          },
          "base_path" => %{
            "type" => "string",
            "description" => "Base directory for relative paths (optional)"
          }
        },
        "required" => ["patch"],
        "additionalProperties" => false
      }
    }
  end

  @impl true
  def invoke(args, context) do
    patch = Map.fetch!(args, "patch")
    base_path = Map.get(args, "base_path", context[:base_path] || File.cwd!())

    with {:ok, changes} <- parse_patch(patch),
         :ok <- maybe_approve(changes, context),
         {:ok, applied} <- apply_changes(changes, base_path, context) do
      {:ok, format_result(applied)}
    end
  end

  defp parse_patch(patch) do
    # Parse unified diff format
    # Returns list of {path, kind, hunks}
    case do_parse(patch) do
      {:ok, changes} -> {:ok, changes}
      {:error, reason} -> {:error, {:parse_error, reason}}
    end
  end

  defp do_parse(patch) do
    lines = String.split(patch, "\n")
    parse_lines(lines, [])
  end

  defp parse_lines([], acc), do: {:ok, Enum.reverse(acc)}
  defp parse_lines(["--- " <> old | ["+++ " <> new | rest]], acc) do
    {hunks, remaining} = parse_hunks(rest, [])
    path = extract_path(new)
    kind = determine_kind(old, new)
    parse_lines(remaining, [{path, kind, hunks} | acc])
  end
  defp parse_lines([_ | rest], acc), do: parse_lines(rest, acc)

  defp parse_hunks(["@@ " <> header | rest], acc) do
    {lines, remaining} = take_hunk_lines(rest, [])
    parse_hunks(remaining, [{header, lines} | acc])
  end
  defp parse_hunks(lines, acc), do: {Enum.reverse(acc), lines}

  defp take_hunk_lines([" " <> line | rest], acc), do: take_hunk_lines(rest, [{:context, line} | acc])
  defp take_hunk_lines(["+" <> line | rest], acc), do: take_hunk_lines(rest, [{:add, line} | acc])
  defp take_hunk_lines(["-" <> line | rest], acc), do: take_hunk_lines(rest, [{:remove, line} | acc])
  defp take_hunk_lines(lines, acc), do: {Enum.reverse(acc), lines}

  defp extract_path(path) do
    path
    |> String.trim_leading("b/")
    |> String.split("\t")
    |> List.first()
  end

  defp determine_kind("/dev/null", _), do: :add
  defp determine_kind(_, "/dev/null"), do: :delete
  defp determine_kind(_, _), do: :modify

  defp maybe_approve(changes, context) do
    case context[:approval] do
      nil -> :ok
      fun when is_function(fun) -> fun.(changes, context)
      module -> module.review_patch(changes, context)
    end
  end

  defp apply_changes(changes, base_path, context) do
    dry_run = Map.get(context, :dry_run, false)

    results = Enum.map(changes, fn {path, kind, hunks} ->
      full_path = Path.join(base_path, path)
      apply_file_change(full_path, kind, hunks, dry_run)
    end)

    if Enum.all?(results, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(results, fn {:ok, r} -> r end)}
    else
      {:error, {:apply_failed, results}}
    end
  end

  defp apply_file_change(path, :add, hunks, dry_run) do
    content = hunks_to_content(hunks)
    unless dry_run do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, content)
    end
    {:ok, %{path: path, kind: :add, applied: true}}
  end

  defp apply_file_change(path, :delete, _hunks, dry_run) do
    unless dry_run, do: File.rm!(path)
    {:ok, %{path: path, kind: :delete, applied: true}}
  end

  defp apply_file_change(path, :modify, hunks, dry_run) do
    content = File.read!(path)
    new_content = apply_hunks(content, hunks)
    unless dry_run, do: File.write!(path, new_content)
    {:ok, %{path: path, kind: :modify, applied: true}}
  end

  defp hunks_to_content(hunks) do
    hunks
    |> Enum.flat_map(fn {_header, lines} ->
      Enum.flat_map(lines, fn
        {:add, line} -> [line]
        {:context, line} -> [line]
        {:remove, _} -> []
      end)
    end)
    |> Enum.join("\n")
  end

  defp apply_hunks(content, hunks) do
    # Simplified hunk application
    # In production, use proper diff algorithm
    lines = String.split(content, "\n")

    Enum.reduce(hunks, lines, fn {_header, hunk_lines}, acc ->
      apply_hunk(acc, hunk_lines)
    end)
    |> Enum.join("\n")
  end

  defp apply_hunk(lines, hunk_lines) do
    # Simplified: just append/remove as encountered
    # Real implementation needs line number tracking
    lines
  end

  defp format_result(applied) do
    %{
      "applied" => length(applied),
      "files" => Enum.map(applied, fn r ->
        %{"path" => r.path, "kind" => to_string(r.kind)}
      end)
    }
  end
end
```

### 2. Register in HostedTools

Update `lib/codex/tools/hosted_tools.ex`.

## Test Requirements (TDD)

### Unit Tests (`test/codex/tools/apply_patch_tool_test.exs`)

```elixir
defmodule Codex.Tools.ApplyPatchToolTest do
  use ExUnit.Case, async: true

  @tmp_dir System.tmp_dir!()

  setup do
    test_dir = Path.join(@tmp_dir, "apply_patch_test_#{:rand.uniform(100000)}")
    File.mkdir_p!(test_dir)
    on_exit(fn -> File.rm_rf!(test_dir) end)
    {:ok, test_dir: test_dir}
  end

  describe "invoke/2" do
    test "creates new file from patch", %{test_dir: dir} do
      patch = """
      --- /dev/null
      +++ b/new_file.txt
      @@ -0,0 +1,3 @@
      +line 1
      +line 2
      +line 3
      """

      args = %{"patch" => patch, "base_path" => dir}
      {:ok, result} = Codex.Tools.ApplyPatchTool.invoke(args, %{})

      assert result["applied"] == 1
      assert File.exists?(Path.join(dir, "new_file.txt"))
    end

    test "deletes file from patch", %{test_dir: dir} do
      file = Path.join(dir, "to_delete.txt")
      File.write!(file, "content")

      patch = """
      --- a/to_delete.txt
      +++ /dev/null
      @@ -1,1 +0,0 @@
      -content
      """

      args = %{"patch" => patch, "base_path" => dir}
      {:ok, result} = Codex.Tools.ApplyPatchTool.invoke(args, %{})

      refute File.exists?(file)
    end

    test "dry run does not modify files", %{test_dir: dir} do
      patch = """
      --- /dev/null
      +++ b/should_not_exist.txt
      @@ -0,0 +1 @@
      +content
      """

      args = %{"patch" => patch, "base_path" => dir}
      {:ok, _} = Codex.Tools.ApplyPatchTool.invoke(args, %{dry_run: true})

      refute File.exists?(Path.join(dir, "should_not_exist.txt"))
    end

    test "respects approval callback", %{test_dir: dir} do
      patch = """
      --- /dev/null
      +++ b/new.txt
      @@ -0,0 +1 @@
      +content
      """

      args = %{"patch" => patch, "base_path" => dir}
      context = %{approval: fn _changes, _ctx -> {:deny, "not allowed"} end}

      assert {:deny, "not allowed"} = Codex.Tools.ApplyPatchTool.invoke(args, context)
    end
  end
end
```

## Verification Criteria

1. [ ] All tests pass
2. [ ] No warnings
3. [ ] No dialyzer errors
4. [ ] No credo issues
5. [ ] Example created and runs

## Update Requirements

### CHANGELOG.md

Add to the existing `## [0.4.5] - 2025-12-30` section:
```markdown
- ApplyPatch hosted tool with `Codex.Tools.ApplyPatchTool`
- Unified diff parsing and application
- Dry-run support for patch validation
- Approval integration for file modifications
```

### Examples

Create `examples/apply_patch_tool.exs` demonstrating patch application.
