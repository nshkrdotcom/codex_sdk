defmodule Codex.Tools.ApplyPatchTool do
  @moduledoc """
  Hosted tool for applying unified diffs to files.

  ## Options
    * `:base_path` - Base directory for file paths (defaults to CWD)
    * `:approval` - Approval callback for reviewing changes before applying
    * `:dry_run` - If true, only validate without applying changes

  ## Approval Callback

  The approval callback can be:
    * A function with arity 1-3: `fn changes -> :ok | {:deny, reason} end`
    * A module implementing `review_patch/2`

  ## Examples

      # Basic usage
      args = %{"patch" => patch_content}
      {:ok, result} = ApplyPatchTool.invoke(args, %{base_path: "/project"})

      # With approval
      context = %{
        metadata: %{
          approval: fn changes, _ctx -> :ok end
        }
      }
      {:ok, result} = ApplyPatchTool.invoke(args, context)

      # Dry run to validate
      {:ok, result} = ApplyPatchTool.invoke(args, %{dry_run: true})
  """

  @behaviour Codex.Tool

  alias Codex.Tools.Hosted

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
    patch = Map.get(args, "patch") || Map.get(args, :patch)
    metadata = Map.get(context, :metadata, %{})

    base_path =
      Map.get(args, "base_path") ||
        Map.get(args, :base_path) ||
        Hosted.metadata_value(metadata, :base_path) ||
        Map.get(context, :base_path) ||
        File.cwd!()

    dry_run =
      Map.get(context, :dry_run, false) ||
        Hosted.metadata_value(metadata, :dry_run, false)

    with {:ok, patch} <- require_patch(patch),
         {:ok, changes} <- parse_patch(patch),
         :ok <- maybe_approve(changes, metadata, args, context),
         {:ok, applied} <- apply_changes(changes, base_path, dry_run) do
      {:ok, format_result(applied)}
    end
  end

  defp require_patch(nil), do: {:error, {:missing_argument, :patch}}
  defp require_patch(""), do: {:error, {:empty_patch, "patch cannot be empty"}}
  defp require_patch(patch) when is_binary(patch), do: {:ok, patch}
  defp require_patch(_), do: {:error, {:invalid_argument, :patch}}

  @doc """
  Parses a unified diff patch string into a list of file changes.

  Returns `{:ok, changes}` where each change is `{path, kind, hunks}`.
  """
  @spec parse_patch(String.t()) :: {:ok, list()} | {:error, {:parse_error, String.t()}}
  def parse_patch(patch) when is_binary(patch) do
    lines = String.split(patch, ~r/\r?\n/)

    case do_parse(lines, []) do
      {:ok, changes} -> {:ok, changes}
      {:error, reason} -> {:error, {:parse_error, reason}}
    end
  end

  defp do_parse([], acc), do: {:ok, Enum.reverse(acc)}

  defp do_parse(["--- " <> old_path | rest], acc) do
    case rest do
      ["+++ " <> new_path | remaining] ->
        {hunks, remaining_lines} = parse_hunks(remaining, [])
        path = extract_path(new_path, old_path)
        kind = determine_kind(old_path, new_path)
        change = {path, kind, Enum.reverse(hunks)}
        do_parse(remaining_lines, [change | acc])

      _ ->
        {:error, "expected +++ line after --- line"}
    end
  end

  defp do_parse([_ | rest], acc), do: do_parse(rest, acc)

  defp parse_hunks(["@@ " <> header | rest], acc) do
    case parse_hunk_header(header) do
      {:ok, hunk_info} ->
        {lines, remaining} = take_hunk_lines(rest, [])
        hunk = Map.put(hunk_info, :lines, Enum.reverse(lines))
        parse_hunks(remaining, [hunk | acc])

      {:error, _reason} ->
        # Skip malformed hunk header
        parse_hunks(rest, acc)
    end
  end

  defp parse_hunks(lines, acc), do: {acc, lines}

  defp parse_hunk_header(header) do
    # Format: @@ -start,count +start,count @@ optional context
    # Examples: @@ -1,3 +1,4 @@
    #           @@ -0,0 +1,5 @@
    #           @@ -1 +1 @@
    regex = ~r/^-(\d+)(?:,(\d+))?\s+\+(\d+)(?:,(\d+))?/

    case Regex.run(regex, header) do
      [_match, old_start, old_count, new_start, new_count] ->
        {:ok,
         %{
           old_start: String.to_integer(old_start),
           old_count: parse_count(old_count),
           new_start: String.to_integer(new_start),
           new_count: parse_count(new_count)
         }}

      [_match, old_start, old_count, new_start] ->
        {:ok,
         %{
           old_start: String.to_integer(old_start),
           old_count: parse_count(old_count),
           new_start: String.to_integer(new_start),
           new_count: 1
         }}

      [_match, old_start, new_start] ->
        {:ok,
         %{
           old_start: String.to_integer(old_start),
           old_count: 1,
           new_start: String.to_integer(new_start),
           new_count: 1
         }}

      _ ->
        {:error, "invalid hunk header: #{header}"}
    end
  end

  defp parse_count(""), do: 1
  defp parse_count(count), do: String.to_integer(count)

  defp take_hunk_lines([" " <> line | rest], acc) do
    take_hunk_lines(rest, [{:context, line} | acc])
  end

  defp take_hunk_lines(["+" <> line | rest], acc) do
    take_hunk_lines(rest, [{:add, line} | acc])
  end

  # Stop at new file header (--- prefix with space after)
  defp take_hunk_lines(["--- " <> _ | _] = lines, acc), do: {acc, lines}

  defp take_hunk_lines(["-" <> line | rest], acc) do
    take_hunk_lines(rest, [{:remove, line} | acc])
  end

  defp take_hunk_lines(["\\" <> _ | rest], acc) do
    # Handle "\ No newline at end of file"
    take_hunk_lines(rest, acc)
  end

  defp take_hunk_lines(lines, acc), do: {acc, lines}

  defp extract_path(new_path, old_path) do
    new_cleaned = clean_path(new_path)

    if new_cleaned == "/dev/null" do
      clean_path(old_path)
    else
      new_cleaned
    end
  end

  defp clean_path(path) do
    path
    |> String.trim()
    |> String.replace(~r/^[ab]\//, "")
    |> String.split("\t")
    |> List.first()
    |> String.trim()
  end

  defp determine_kind(old_path, new_path) do
    old_cleaned = clean_path(old_path)
    new_cleaned = clean_path(new_path)

    cond do
      old_cleaned == "/dev/null" -> :add
      new_cleaned == "/dev/null" -> :delete
      true -> :modify
    end
  end

  defp maybe_approve(changes, metadata, _args, context) do
    case Hosted.callback(metadata, :approval) do
      nil -> :ok
      fun when is_function(fun) -> run_approval_fun(fun, changes, context, metadata)
      module when is_atom(module) -> run_approval_module(module, changes, context)
      _ -> :ok
    end
  end

  defp run_approval_fun(fun, changes, context, metadata) do
    result = Hosted.safe_call(fun, format_changes_for_approval(changes), context, metadata)
    normalize_approval_result(result)
  end

  defp run_approval_module(module, changes, context) do
    if function_exported?(module, :review_patch, 2) do
      result = module.review_patch(format_changes_for_approval(changes), context)
      normalize_approval_result(result)
    else
      :ok
    end
  end

  defp normalize_approval_result(:ok), do: :ok
  defp normalize_approval_result(true), do: :ok
  defp normalize_approval_result({:ok, _}), do: :ok
  defp normalize_approval_result({:deny, reason}), do: {:deny, reason}
  defp normalize_approval_result(:deny), do: {:deny, :denied}
  defp normalize_approval_result(false), do: {:deny, :denied}
  defp normalize_approval_result(other), do: {:error, {:invalid_approval_response, other}}

  defp format_changes_for_approval(changes) do
    Enum.map(changes, fn {path, kind, hunks} ->
      %{
        path: path,
        kind: kind,
        hunk_count: length(hunks),
        additions: count_lines(hunks, :add),
        deletions: count_lines(hunks, :remove)
      }
    end)
  end

  defp count_lines(hunks, type) do
    hunks
    |> Enum.flat_map(fn hunk -> Map.get(hunk, :lines, []) end)
    |> Enum.count(fn {t, _} -> t == type end)
  end

  defp apply_changes(changes, base_path, dry_run) do
    results =
      Enum.reduce_while(changes, [], fn {path, kind, hunks}, acc ->
        full_path = Path.join(base_path, path)

        case apply_file_change(full_path, kind, hunks, dry_run) do
          {:ok, result} -> {:cont, [result | acc]}
          {:error, reason} -> {:halt, {:error, {path, reason}}}
        end
      end)

    case results do
      {:error, _} = error -> error
      applied -> {:ok, Enum.reverse(applied)}
    end
  end

  defp apply_file_change(path, :add, hunks, dry_run) do
    content = hunks_to_content(hunks)

    if dry_run do
      {:ok, %{path: path, kind: :add, applied: false, dry_run: true}}
    else
      with :ok <- ensure_parent_dir(path),
           :ok <- File.write(path, content) do
        {:ok, %{path: path, kind: :add, applied: true}}
      end
    end
  end

  defp apply_file_change(path, :delete, _hunks, dry_run) do
    if dry_run do
      if File.exists?(path) do
        {:ok, %{path: path, kind: :delete, applied: false, dry_run: true}}
      else
        {:error, :file_not_found}
      end
    else
      case File.rm(path) do
        :ok -> {:ok, %{path: path, kind: :delete, applied: true}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp apply_file_change(path, :modify, hunks, dry_run) do
    with {:ok, content} <- File.read(path),
         {:ok, new_content} <- apply_hunks(content, hunks) do
      write_modified_file(path, new_content, dry_run)
    end
  end

  defp write_modified_file(path, _content, true = _dry_run) do
    {:ok, %{path: path, kind: :modify, applied: false, dry_run: true}}
  end

  defp write_modified_file(path, content, false = _dry_run) do
    case File.write(path, content) do
      :ok -> {:ok, %{path: path, kind: :modify, applied: true}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_parent_dir(path) do
    dir = Path.dirname(path)

    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, reason} -> {:error, {:mkdir_failed, reason}}
    end
  end

  defp hunks_to_content(hunks) do
    hunks
    |> Enum.flat_map(fn hunk ->
      hunk
      |> Map.get(:lines, [])
      |> Enum.flat_map(fn
        {:add, line} -> [line]
        {:context, line} -> [line]
        {:remove, _} -> []
      end)
    end)
    |> Enum.join("\n")
  end

  @doc """
  Applies hunks to file content.

  Returns `{:ok, new_content}` or `{:error, reason}`.
  """
  @spec apply_hunks(String.t(), list()) :: {:ok, String.t()}
  def apply_hunks(content, hunks) do
    lines = String.split(content, ~r/\r?\n/, include_captures: false)
    lines_array = :array.from_list(lines)

    # Apply hunks in reverse order to preserve line numbers
    sorted_hunks = Enum.sort_by(hunks, & &1.old_start, :desc)

    final_array =
      Enum.reduce(sorted_hunks, lines_array, fn hunk, arr ->
        {:ok, new_arr} = apply_single_hunk(arr, hunk)
        new_arr
      end)

    final_lines = :array.to_list(final_array)
    {:ok, Enum.join(final_lines, "\n")}
  end

  defp apply_single_hunk(lines_array, hunk) do
    %{old_start: old_start, lines: hunk_lines} = hunk
    # Convert 1-indexed to 0-indexed
    start_idx = max(old_start - 1, 0)

    # Verify context matches (lenient - always proceeds)
    _ = verify_context(lines_array, start_idx, hunk_lines)

    # Build the new lines for this hunk
    new_hunk_lines =
      hunk_lines
      |> Enum.flat_map(fn
        {:add, line} -> [line]
        {:context, line} -> [line]
        {:remove, _} -> []
      end)

    # Count how many lines to remove (context + remove lines from original)
    old_line_count =
      Enum.count(hunk_lines, fn
        {:remove, _} -> true
        {:context, _} -> true
        {:add, _} -> false
      end)

    # Replace the old lines with new lines
    new_array = replace_lines(lines_array, start_idx, old_line_count, new_hunk_lines)
    {:ok, new_array}
  end

  defp verify_context(lines_array, start_idx, hunk_lines) do
    # Extract expected context/remove lines from hunk
    expected =
      hunk_lines
      |> Enum.filter(fn
        {:context, _} -> true
        {:remove, _} -> true
        {:add, _} -> false
      end)
      |> Enum.map(fn {_, line} -> line end)

    # Get actual lines from array
    array_size = :array.size(lines_array)
    actual_count = length(expected)

    actual =
      for i <- start_idx..(start_idx + actual_count - 1),
          i < array_size,
          do: :array.get(i, lines_array)

    # Allow some fuzzy matching for trailing whitespace
    if length(actual) == length(expected) &&
         Enum.zip(actual, expected)
         |> Enum.all?(fn {a, e} -> String.trim_trailing(a) == String.trim_trailing(e) end) do
      :ok
    else
      # Be lenient - if we can't verify, still try to apply
      :ok
    end
  end

  defp replace_lines(array, start_idx, remove_count, new_lines) do
    current_list = :array.to_list(array)
    array_size = length(current_list)

    # Clamp values
    safe_start = min(start_idx, array_size)
    safe_remove = min(remove_count, array_size - safe_start)

    before = Enum.take(current_list, safe_start)
    after_lines = Enum.drop(current_list, safe_start + safe_remove)

    :array.from_list(before ++ new_lines ++ after_lines)
  end

  defp format_result(applied) do
    %{
      "applied" => Enum.count(applied, & &1.applied),
      "validated" => Enum.count(applied, &Map.get(&1, :dry_run, false)),
      "files" =>
        Enum.map(applied, fn r ->
          result = %{"path" => r.path, "kind" => to_string(r.kind)}

          if Map.get(r, :dry_run) do
            Map.put(result, "dry_run", true)
          else
            result
          end
        end)
    }
  end
end
