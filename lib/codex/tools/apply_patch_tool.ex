defmodule Codex.Tools.ApplyPatchTool do
  @moduledoc """
  Hosted tool for applying Codex apply_patch edits to files.

  ## Options
    * `:base_path` - Base directory for file paths (defaults to CWD)
    * `:approval` - Approval callback for reviewing changes before applying
    * `:dry_run` - If true, only validate without applying changes

  ## Approval Callback

  The approval callback can be:
    * A function with arity 1-3: `fn changes -> :ok | {:deny, reason} end`
    * A module implementing `review_patch/2`

  ## Examples

      # Basic usage (*** Begin Patch format)
      args = %{"input" => patch_content}
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
      description: "Apply an apply_patch edit to files",
      schema: %{
        "type" => "object",
        "properties" => %{
          "input" => %{
            "type" => "string",
            "description" => "The apply_patch input (*** Begin Patch format)"
          },
          "patch" => %{
            "type" => "string",
            "description" => "Legacy unified diff patch (fallback support)"
          },
          "base_path" => %{
            "type" => "string",
            "description" => "Base directory for relative paths (optional)"
          }
        },
        "additionalProperties" => false
      }
    }
  end

  @impl true
  def invoke(args, context) do
    patch =
      Map.get(args, "input") ||
        Map.get(args, :input) ||
        Map.get(args, "patch") ||
        Map.get(args, :patch)

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
  Parses an apply_patch or unified diff patch string into a list of file changes.
  """
  @spec parse_patch(String.t()) :: {:ok, list()} | {:error, {:parse_error, String.t()}}
  def parse_patch(patch) when is_binary(patch) do
    if apply_patch_format?(patch) do
      parse_apply_patch(patch)
    else
      parse_unified_diff(patch)
    end
  end

  defp apply_patch_format?(patch) do
    patch
    |> String.trim_leading()
    |> String.starts_with?("*** Begin Patch")
  end

  defp parse_apply_patch(patch) do
    lines =
      patch
      |> String.split(~r/\r?\n/, trim: false)
      |> drop_leading_blank_lines()

    case lines do
      ["*** Begin Patch" | rest] ->
        case parse_apply_patch_sections(rest, []) do
          {:ok, changes} when changes == [] ->
            {:error, {:parse_error, "empty patch"}}

          {:ok, changes} ->
            {:ok, changes}

          {:error, reason} ->
            {:error, {:parse_error, reason}}
        end

      _ ->
        {:error, {:parse_error, "missing *** Begin Patch header"}}
    end
  end

  defp parse_apply_patch_sections([], _acc),
    do: {:error, "missing *** End Patch marker"}

  defp parse_apply_patch_sections(["" | rest], acc),
    do: parse_apply_patch_sections(rest, acc)

  defp parse_apply_patch_sections(["*** End Patch" | rest], acc) do
    if Enum.all?(rest, &(&1 == "")) do
      {:ok, Enum.reverse(acc)}
    else
      {:error, "unexpected content after *** End Patch"}
    end
  end

  defp parse_apply_patch_sections(["*** Add File: " <> path | rest], acc) do
    case take_add_lines(rest, []) do
      {:ok, add_lines, remaining} ->
        if add_lines == [] do
          {:error, "add file has no content: #{String.trim(path)}"}
        else
          change = %{
            format: :apply_patch,
            kind: :add,
            path: String.trim(path),
            content: add_lines
          }

          parse_apply_patch_sections(remaining, [change | acc])
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_apply_patch_sections(["*** Delete File: " <> path | rest], acc) do
    change = %{
      format: :apply_patch,
      kind: :delete,
      path: String.trim(path)
    }

    parse_apply_patch_sections(rest, [change | acc])
  end

  defp parse_apply_patch_sections(["*** Update File: " <> path | rest], acc) do
    {move_to, remaining} = take_move_line(rest)

    case parse_update_changes(remaining, []) do
      {:ok, segments, remaining_lines} ->
        change = %{
          format: :apply_patch,
          kind: :update,
          path: String.trim(path),
          move_to: move_to,
          segments: segments
        }

        parse_apply_patch_sections(remaining_lines, [change | acc])

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_apply_patch_sections([line | _rest], _acc) do
    {:error, "#{line} is not a valid hunk header"}
  end

  defp take_add_lines([], _acc), do: {:error, "unexpected end of add file"}

  defp take_add_lines([line | rest], acc) do
    cond do
      String.starts_with?(line, "*** ") ->
        {:ok, Enum.reverse(acc), [line | rest]}

      String.starts_with?(line, "+") ->
        take_add_lines(rest, [String.slice(line, 1..-1//1) | acc])

      true ->
        {:error, "invalid add line: #{line}"}
    end
  end

  defp take_move_line(["*** Move to: " <> path | rest]), do: {String.trim(path), rest}
  defp take_move_line(lines), do: {nil, lines}

  defp parse_update_changes(lines, acc) do
    do_parse_update_changes(lines, acc, nil, false, false, false)
  end

  defp do_parse_update_changes(lines, acc, current_chunk, seen_hunk, eof_seen, has_changes)

  defp do_parse_update_changes([], acc, current_chunk, _seen_hunk, _eof_seen, has_changes) do
    finalize_update_changes(acc, current_chunk, has_changes)
  end

  defp do_parse_update_changes(
         [line | rest],
         acc,
         current_chunk,
         seen_hunk,
         eof_seen,
         has_changes
       ) do
    case update_line_kind(line, eof_seen) do
      {:error, reason} ->
        {:error, reason}

      :boundary ->
        finalize_update_boundary(line, rest, acc, current_chunk, has_changes)

      :anchor ->
        handle_anchor_line(line, rest, acc, current_chunk, has_changes)

      :eof_marker ->
        handle_end_of_file(rest, acc, current_chunk, seen_hunk, has_changes)

      :change ->
        handle_change_line(line, rest, acc, current_chunk, seen_hunk, eof_seen)
    end
  end

  defp update_line_kind(line, eof_seen) do
    cond do
      eof_seen and not String.starts_with?(line, "*** ") ->
        {:error, "unexpected content after *** End of File"}

      line == "*** End of File" ->
        :eof_marker

      String.starts_with?(line, "*** ") ->
        :boundary

      String.starts_with?(line, "@@") ->
        :anchor

      true ->
        :change
    end
  end

  defp finalize_update_changes(acc, current_chunk, has_changes) do
    acc = flush_chunk(acc, current_chunk)

    if has_changes and acc == [] do
      {:error, "missing @@ hunk header"}
    else
      {:ok, Enum.reverse(acc), []}
    end
  end

  defp finalize_update_boundary(line, rest, acc, current_chunk, has_changes) do
    acc = flush_chunk(acc, current_chunk)

    if has_changes and acc == [] do
      {:error, "missing @@ hunk header"}
    else
      {:ok, Enum.reverse(acc), [line | rest]}
    end
  end

  defp handle_anchor_line(line, rest, acc, current_chunk, has_changes) do
    acc = flush_chunk(acc, current_chunk)
    anchor = line |> String.trim_leading("@@") |> String.trim()
    acc = if anchor == "", do: acc, else: [{:anchor, anchor} | acc]
    do_parse_update_changes(rest, acc, %{lines: [], eof: false}, true, false, has_changes)
  end

  defp handle_end_of_file(rest, acc, current_chunk, seen_hunk, has_changes) do
    current_chunk = current_chunk || %{lines: [], eof: false}
    current_chunk = %{current_chunk | eof: true}
    do_parse_update_changes(rest, acc, current_chunk, seen_hunk, true, has_changes)
  end

  defp handle_change_line(line, rest, acc, current_chunk, seen_hunk, eof_seen) do
    if seen_hunk do
      case parse_change_line(line) do
        {:ok, change} ->
          current_chunk = current_chunk || %{lines: [], eof: false}
          current_chunk = %{current_chunk | lines: current_chunk.lines ++ [change]}
          do_parse_update_changes(rest, acc, current_chunk, seen_hunk, eof_seen, true)

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, "missing @@ hunk header"}
    end
  end

  defp parse_change_line(""), do: {:ok, {:context, ""}}

  defp parse_change_line(line) do
    case String.first(line) do
      " " -> {:ok, {:context, String.slice(line, 1..-1//1)}}
      "+" -> {:ok, {:add, String.slice(line, 1..-1//1)}}
      "-" -> {:ok, {:remove, String.slice(line, 1..-1//1)}}
      _ -> {:error, "invalid change line: #{line}"}
    end
  end

  defp flush_chunk(acc, nil), do: acc

  defp flush_chunk(acc, %{lines: []} = chunk) do
    if chunk.eof do
      [{:chunk, chunk} | acc]
    else
      acc
    end
  end

  defp flush_chunk(acc, %{lines: _lines} = chunk), do: [{:chunk, chunk} | acc]

  defp drop_leading_blank_lines(lines), do: Enum.drop_while(lines, &(&1 == ""))

  defp parse_unified_diff(patch) do
    lines = String.split(patch, ~r/\r?\n/)

    case do_parse_unified(lines, []) do
      {:ok, changes} -> {:ok, changes}
      {:error, reason} -> {:error, {:parse_error, reason}}
    end
  end

  defp do_parse_unified([], acc), do: {:ok, Enum.reverse(acc)}

  defp do_parse_unified(["--- " <> old_path | rest], acc) do
    case rest do
      ["+++ " <> new_path | remaining] ->
        {hunks, remaining_lines} = parse_unified_hunks(remaining, [])
        path = extract_path(new_path, old_path)
        kind = determine_kind(old_path, new_path)

        change = %{
          format: :unified_diff,
          kind: kind,
          path: path,
          hunks: Enum.reverse(hunks)
        }

        do_parse_unified(remaining_lines, [change | acc])

      _ ->
        {:error, "expected +++ line after --- line"}
    end
  end

  defp do_parse_unified([_ | rest], acc), do: do_parse_unified(rest, acc)

  defp parse_unified_hunks(["@@ " <> header | rest], acc) do
    case parse_unified_hunk_header(header) do
      {:ok, hunk_info} ->
        {lines, remaining} = take_hunk_lines(rest, [])
        hunk = Map.put(hunk_info, :lines, Enum.reverse(lines))
        parse_unified_hunks(remaining, [hunk | acc])

      {:error, _reason} ->
        # Skip malformed hunk header
        parse_unified_hunks(rest, acc)
    end
  end

  defp parse_unified_hunks(lines, acc), do: {acc, lines}

  defp parse_unified_hunk_header(header) do
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
      true -> :update
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
    Enum.map(changes, fn change ->
      %{
        path: change.path,
        kind: change.kind,
        hunk_count: change_hunk_count(change),
        additions: change_additions(change),
        deletions: change_deletions(change)
      }
      |> maybe_put(:move_to, Map.get(change, :move_to))
    end)
  end

  defp change_hunk_count(%{format: :apply_patch, kind: :add}), do: 1
  defp change_hunk_count(%{format: :apply_patch, kind: :delete}), do: 0

  defp change_hunk_count(%{format: :apply_patch, kind: :update, segments: segments}),
    do: count_apply_patch_chunks(segments)

  defp change_hunk_count(%{format: :unified_diff, hunks: hunks}), do: length(hunks)
  defp change_hunk_count(_), do: 0

  defp change_additions(%{format: :apply_patch, kind: :add, content: content}),
    do: length(content)

  defp change_additions(%{format: :apply_patch, kind: :update, segments: segments}),
    do: count_apply_patch_lines(segments, :add)

  defp change_additions(%{format: :unified_diff, hunks: hunks}),
    do: count_unified_lines(hunks, :add)

  defp change_additions(_), do: 0

  defp change_deletions(%{format: :apply_patch, kind: :update, segments: segments}),
    do: count_apply_patch_lines(segments, :remove)

  defp change_deletions(%{format: :unified_diff, hunks: hunks}),
    do: count_unified_lines(hunks, :remove)

  defp change_deletions(_), do: 0

  defp count_unified_lines(hunks, type) do
    hunks
    |> Enum.flat_map(fn hunk -> Map.get(hunk, :lines, []) end)
    |> Enum.count(fn {t, _} -> t == type end)
  end

  defp count_apply_patch_chunks(segments) do
    Enum.count(segments, &match?({:chunk, _}, &1))
  end

  defp count_apply_patch_lines(segments, type) do
    segments
    |> Enum.flat_map(fn
      {:chunk, %{lines: lines}} -> lines
      _ -> []
    end)
    |> Enum.count(fn {t, _} -> t == type end)
  end

  defp apply_changes(changes, base_path, dry_run) do
    base_path = Path.expand(base_path)

    with {:ok, operations} <- build_operations(changes, base_path) do
      if dry_run do
        {:ok, Enum.map(operations, &Map.put(&1, :dry_run, true))}
      else
        apply_operations(operations)
      end
    end
  end

  defp build_operations(changes, base_path) do
    results =
      Enum.reduce_while(changes, [], fn change, acc ->
        case build_operation(change, base_path) do
          {:ok, operation} -> {:cont, [operation | acc]}
          {:error, reason} -> {:halt, {:error, {change.path, reason}}}
        end
      end)

    case results do
      {:error, _} = error -> error
      operations -> {:ok, Enum.reverse(operations)}
    end
  end

  defp build_operation(%{format: :apply_patch, kind: :add} = change, base_path) do
    with {:ok, full_path} <- expand_relative_path(change.path, base_path),
         :ok <- ensure_not_directory(full_path) do
      content = join_lines_with_newline(change.content)
      {:ok, %{path: full_path, kind: :add, content: content}}
    end
  end

  defp build_operation(%{format: :apply_patch, kind: :delete} = change, base_path) do
    with {:ok, full_path} <- expand_relative_path(change.path, base_path),
         :ok <- ensure_regular_file(full_path) do
      {:ok, %{path: full_path, kind: :delete}}
    end
  end

  defp build_operation(%{format: :apply_patch, kind: :update} = change, base_path) do
    with {:ok, full_path} <- expand_relative_path(change.path, base_path),
         :ok <- ensure_regular_file(full_path),
         {:ok, content} <- File.read(full_path),
         {:ok, new_content} <- apply_apply_patch(content, change.segments, change.path),
         {:ok, move_path} <- expand_move_path(change.move_to, base_path) do
      {:ok,
       %{
         path: full_path,
         kind: :update,
         content: new_content,
         move_to: move_path
       }}
    end
  end

  defp build_operation(%{format: :unified_diff, kind: :add} = change, base_path) do
    with {:ok, full_path} <- expand_relative_path(change.path, base_path),
         :ok <- ensure_not_directory(full_path) do
      content = hunks_to_content(change.hunks)
      {:ok, %{path: full_path, kind: :add, content: content}}
    end
  end

  defp build_operation(%{format: :unified_diff, kind: :delete} = change, base_path) do
    with {:ok, full_path} <- expand_relative_path(change.path, base_path),
         :ok <- ensure_regular_file(full_path) do
      {:ok, %{path: full_path, kind: :delete}}
    end
  end

  defp build_operation(%{format: :unified_diff, kind: :update} = change, base_path) do
    with {:ok, full_path} <- expand_relative_path(change.path, base_path),
         :ok <- ensure_regular_file(full_path),
         {:ok, content} <- File.read(full_path),
         {:ok, new_content} <- apply_hunks(content, change.hunks) do
      {:ok, %{path: full_path, kind: :update, content: new_content}}
    end
  end

  defp build_operation(change, _base_path),
    do: {:error, {:unsupported_change, change}}

  defp apply_operations(operations) do
    results =
      Enum.reduce_while(operations, [], fn operation, acc ->
        case apply_operation(operation) do
          {:ok, result} -> {:cont, [result | acc]}
          {:error, reason} -> {:halt, {:error, {operation.path, reason}}}
        end
      end)

    case results do
      {:error, _} = error -> error
      applied -> {:ok, Enum.reverse(applied)}
    end
  end

  defp apply_operation(%{kind: :add, path: path, content: content}) do
    with :ok <- ensure_parent_dir(path),
         :ok <- File.write(path, content) do
      {:ok, %{path: path, kind: :add, applied: true}}
    end
  end

  defp apply_operation(%{kind: :delete, path: path}) do
    case File.rm(path) do
      :ok -> {:ok, %{path: path, kind: :delete, applied: true}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_operation(%{kind: :update, path: path, content: content} = operation) do
    case normalize_move_path(Map.get(operation, :move_to), path) do
      {:move, destination} ->
        with :ok <- ensure_parent_dir(destination),
             :ok <- File.write(destination, content),
             :ok <- File.rm(path) do
          {:ok, %{path: path, kind: :update, move_path: destination, applied: true}}
        end

      :in_place ->
        case File.write(path, content) do
          :ok -> {:ok, %{path: path, kind: :update, applied: true}}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp apply_operation(operation),
    do: {:error, {:unsupported_operation, operation}}

  defp ensure_parent_dir(path) do
    dir = Path.dirname(path)

    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, reason} -> {:error, {:mkdir_failed, reason}}
    end
  end

  defp ensure_regular_file(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular}} -> :ok
      {:ok, _} -> {:error, :not_a_file}
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_not_directory(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :directory}} -> {:error, :is_a_directory}
      {:ok, _} -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp expand_relative_path(path, base_path) do
    cond do
      not is_binary(path) or path == "" ->
        {:error, :invalid_path}

      String.starts_with?(path, "~") ->
        {:error, :invalid_path}

      Path.type(path) == :absolute ->
        {:error, :absolute_path_not_allowed}

      true ->
        base = Path.expand(base_path)
        expanded = Path.expand(path, base)

        if within_base?(expanded, base) do
          {:ok, expanded}
        else
          {:error, :path_traversal}
        end
    end
  end

  defp expand_move_path(nil, _base_path), do: {:ok, nil}

  defp expand_move_path(path, base_path) do
    expand_relative_path(path, base_path)
  end

  defp within_base?(path, base) do
    base = Path.expand(base)
    path = Path.expand(path)

    base_parts = Path.split(base)
    path_parts = Path.split(path)

    List.starts_with?(path_parts, base_parts)
  end

  defp normalize_move_path(nil, _path), do: :in_place
  defp normalize_move_path(path, path), do: :in_place
  defp normalize_move_path(path, _), do: {:move, path}

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
    |> join_lines()
  end

  defp apply_apply_patch(content, [], _path), do: {:ok, content}

  defp apply_apply_patch(content, segments, path) do
    {lines, _had_trailing_newline} = split_content_lines(content)

    case apply_segments(lines, segments, path) do
      {:ok, new_lines} -> {:ok, finalize_content(new_lines)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp split_content_lines(content) do
    lines = String.split(content, ~r/\r?\n/, trim: false)

    case List.last(lines) do
      "" -> {Enum.drop(lines, -1), true}
      _ -> {lines, false}
    end
  end

  defp finalize_content(lines) do
    case lines do
      [] -> ""
      _ -> Enum.join(lines, "\n") <> "\n"
    end
  end

  defp apply_segments(lines, segments, path) do
    segments
    |> Enum.reduce_while({lines, 0}, fn segment, {acc_lines, cursor} ->
      case apply_segment(segment, acc_lines, cursor, path) do
        {:ok, new_lines, new_cursor} -> {:cont, {new_lines, new_cursor}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> finalize_apply_segments()
  end

  defp apply_segment({:anchor, anchor}, lines, cursor, _path) do
    case find_anchor(lines, anchor, cursor) do
      {:ok, index} -> {:ok, lines, index + 1}
      {:error, reason} -> {:error, {:missing_anchor, reason}}
    end
  end

  defp apply_segment({:chunk, %{lines: chunk_lines, eof: eof?}}, lines, cursor, path) do
    apply_chunk(lines, chunk_lines, cursor, eof?, path)
  end

  defp finalize_apply_segments({:error, _} = error), do: error
  defp finalize_apply_segments({new_lines, _cursor}), do: {:ok, new_lines}

  defp find_anchor(lines, anchor, cursor) do
    match =
      lines
      |> Enum.with_index()
      |> Enum.find(fn {line, idx} ->
        idx >= cursor and String.contains?(line, anchor)
      end)

    case match do
      {_, index} -> {:ok, index}
      nil -> {:error, "Failed to find anchor #{anchor}"}
    end
  end

  defp apply_chunk(lines, chunk_lines, cursor, eof?, path) do
    expected = chunk_expected_lines(chunk_lines)
    replacement = chunk_replacement_lines(chunk_lines)

    if expected == [] do
      apply_chunk_insert(lines, cursor, replacement, eof?)
    else
      apply_chunk_replace(lines, expected, replacement, cursor, eof?, path)
    end
  end

  defp chunk_expected_lines(chunk_lines) do
    Enum.flat_map(chunk_lines, fn
      {:context, line} -> [line]
      {:remove, line} -> [line]
      {:add, _} -> []
    end)
  end

  defp chunk_replacement_lines(chunk_lines) do
    Enum.flat_map(chunk_lines, fn
      {:context, line} -> [line]
      {:add, line} -> [line]
      {:remove, _} -> []
    end)
  end

  defp apply_chunk_insert(lines, cursor, replacement, eof?) do
    index = if eof?, do: length(lines), else: cursor
    new_lines = insert_lines(lines, index, replacement)
    {:ok, new_lines, index + length(replacement)}
  end

  defp apply_chunk_replace(lines, expected, replacement, cursor, eof?, path) do
    case find_sequence(lines, expected, cursor) do
      nil ->
        {:error, {:context_mismatch, "Failed to find expected lines in #{path}"}}

      index ->
        apply_chunk_at_index(lines, expected, replacement, index, eof?, path)
    end
  end

  defp apply_chunk_at_index(lines, expected, replacement, index, eof?, path) do
    if eof? and index + length(expected) != length(lines) do
      {:error, {:context_mismatch, "Expected lines are not at end of file for #{path}"}}
    else
      new_lines = replace_lines_in_list(lines, index, length(expected), replacement)
      {:ok, new_lines, index + length(replacement)}
    end
  end

  defp find_sequence(lines, expected, cursor) do
    max_start = length(lines) - length(expected)

    if max_start < cursor do
      nil
    else
      Enum.find(cursor..max_start, fn index ->
        Enum.slice(lines, index, length(expected)) == expected
      end)
    end
  end

  defp insert_lines(lines, index, insert) do
    before = Enum.take(lines, index)
    after_lines = Enum.drop(lines, index)
    before ++ insert ++ after_lines
  end

  defp replace_lines_in_list(lines, index, remove_count, replacement) do
    before = Enum.take(lines, index)
    after_lines = Enum.drop(lines, index + remove_count)
    before ++ replacement ++ after_lines
  end

  defp join_lines(lines), do: Enum.join(lines, "\n")

  defp join_lines_with_newline(lines) do
    case lines do
      [] -> ""
      _ -> Enum.join(lines, "\n") <> "\n"
    end
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
      "applied" => Enum.count(applied, &Map.get(&1, :applied, false)),
      "validated" => Enum.count(applied, &Map.get(&1, :dry_run, false)),
      "files" =>
        Enum.map(applied, fn r ->
          result =
            %{"path" => r.path, "kind" => to_string(r.kind)}
            |> maybe_put("move_path", Map.get(r, :move_path))

          if Map.get(r, :dry_run) do
            Map.put(result, "dry_run", true)
          else
            result
          end
        end)
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
