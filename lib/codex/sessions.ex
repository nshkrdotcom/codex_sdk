defmodule Codex.Sessions do
  @moduledoc """
  Helpers for inspecting Codex CLI session files and replaying recorded changes.
  """

  alias Codex.Items
  alias Codex.Runtime.Erlexec

  @default_sessions_dir Path.expand("~/.codex/sessions")
  @default_apply_timeout_ms 60_000

  @type session_entry :: %{
          id: String.t(),
          path: String.t(),
          started_at: String.t() | nil,
          updated_at: String.t() | nil,
          cwd: String.t() | nil,
          originator: String.t() | nil,
          cli_version: String.t() | nil,
          metadata: map()
        }

  @type apply_result :: %{
          stdout: String.t(),
          stderr: String.t(),
          exit_code: integer(),
          success: boolean()
        }

  @doc """
  Lists known sessions by scanning the sessions directory.

  ## Options

  - `:sessions_dir` - Override the default session directory.
  """
  @spec list_sessions(keyword()) :: {:ok, [session_entry()]} | {:error, term()}
  def list_sessions(opts \\ []) do
    sessions_dir = Keyword.get(opts, :sessions_dir, @default_sessions_dir)

    case File.stat(sessions_dir) do
      {:ok, %File.Stat{type: :directory}} -> {:ok, collect_entries(sessions_dir)}
      {:error, :enoent} -> {:ok, []}
      {:ok, _} -> {:error, :not_a_directory}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Applies a unified diff or file_change items to the local working tree.

  Accepts either a diff string or a list of `%Codex.Items.FileChange{}` structs
  (or raw change maps with `path`, `kind`, and `diff` fields).
  """
  @spec apply(String.t() | list(), keyword()) :: {:ok, apply_result()} | {:error, term()}
  def apply(input, opts \\ []) do
    with {:ok, patch} <- normalize_apply_input(input) do
      apply_patch(patch, opts)
    end
  end

  @doc """
  Restores the working tree using a ghost snapshot item.

  Accepts a `%Codex.Items.GhostSnapshot{}` struct, a raw response item map, or a
  ghost commit map with `id` and preexisting untracked fields.
  """
  @spec undo(term(), keyword()) :: {:ok, map()} | {:error, term()}
  def undo(snapshot, opts \\ []) do
    with {:ok, ghost_commit} <- normalize_ghost_commit(snapshot),
         {:ok, repo_root} <- repo_root(Keyword.get(opts, :cwd, File.cwd!())),
         {:ok, prefix} <- repo_prefix(repo_root, Keyword.get(opts, :cwd, File.cwd!())),
         :ok <- restore_git_snapshot(repo_root, prefix, ghost_commit) do
      cleanup_untracked(repo_root, ghost_commit)
    end
  end

  defp collect_entries(sessions_dir) do
    sessions_dir
    |> session_files()
    |> Enum.map(&build_entry/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.updated_at, :desc)
  end

  defp session_files(sessions_dir) do
    jsonl = Path.wildcard(Path.join(sessions_dir, "**/*.jsonl"))
    json = Path.wildcard(Path.join(sessions_dir, "**/*.json"))
    Enum.uniq(jsonl ++ json)
  end

  defp build_entry(path) do
    case read_first_line(path) do
      {:ok, line} ->
        entry_from_meta(path, decode_session_meta(line))

      {:error, :empty} ->
        entry_from_meta(path, %{})

      {:error, _reason} ->
        nil
    end
  end

  defp entry_from_meta(path, meta) when is_map(meta) do
    metadata = Map.get(meta, :metadata)

    %{
      id: Map.get(meta, :id) || fallback_id(path),
      path: path,
      started_at: Map.get(meta, :started_at),
      updated_at: stat_updated_at(path),
      cwd: Map.get(meta, :cwd),
      originator: Map.get(meta, :originator),
      cli_version: Map.get(meta, :cli_version),
      metadata: if(is_map(metadata), do: metadata, else: %{})
    }
  end

  defp read_first_line(path) do
    case File.open(path, [:read]) do
      {:ok, io} ->
        line = IO.read(io, :line)
        File.close(io)

        if line == :eof do
          {:error, :empty}
        else
          {:ok, line}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_session_meta(line) when is_binary(line) do
    line
    |> String.trim()
    |> parse_session_line()
  end

  defp parse_session_line(""), do: %{}

  defp parse_session_line(line) do
    case Jason.decode(line) do
      {:ok, raw} when is_map(raw) -> build_session_meta(raw)
      _ -> %{}
    end
  end

  defp build_session_meta(raw) do
    payload = Map.get(raw, "payload", %{})
    metadata = extract_session_metadata(raw, payload)

    %{
      id: first_present([payload["id"], payload["thread_id"], raw["id"], raw["thread_id"]]),
      started_at: first_present([payload["timestamp"], raw["timestamp"]]),
      cwd: first_present([payload["cwd"], raw["cwd"]]),
      originator: first_present([payload["originator"], raw["originator"]]),
      cli_version: first_present([payload["cli_version"], raw["cli_version"]]),
      metadata: metadata
    }
  end

  defp extract_session_metadata(raw, payload) do
    payload_meta =
      if is_map(payload) do
        Map.drop(payload, ~w(id thread_id timestamp cwd originator cli_version))
      else
        %{}
      end

    raw_meta = Map.drop(raw, ~w(id thread_id timestamp cwd originator cli_version payload type))

    Map.merge(raw_meta, payload_meta)
  end

  defp first_present(values) do
    Enum.find(values, fn value -> not is_nil(value) end)
  end

  defp fallback_id(path) do
    basename = Path.basename(path)

    basename
    |> String.replace_suffix(".jsonl", "")
    |> String.replace_suffix(".json", "")
  end

  defp stat_updated_at(path) do
    with {:ok, %File.Stat{mtime: mtime}} <- File.stat(path),
         {:ok, naive} <- NaiveDateTime.from_erl(mtime) do
      NaiveDateTime.to_iso8601(naive)
    else
      _ -> nil
    end
  end

  defp normalize_apply_input(patch) when is_binary(patch) do
    patch = patch |> String.trim_trailing() |> ensure_trailing_newline()
    if patch == "\n", do: {:error, :empty_patch}, else: {:ok, patch}
  end

  defp normalize_apply_input(items) when is_list(items) do
    cond do
      items == [] ->
        {:error, :empty_patch}

      Enum.all?(items, &match?(%Items.FileChange{}, &1)) ->
        items
        |> Enum.flat_map(& &1.changes)
        |> changes_to_patch()

      Enum.all?(items, &is_map/1) ->
        items
        |> normalize_change_items()
        |> changes_to_patch()

      true ->
        {:error, {:invalid_apply_input, items}}
    end
  end

  defp normalize_apply_input(_), do: {:error, :invalid_apply_input}

  defp normalize_change_items(items) do
    if Enum.any?(items, &has_changes_key?/1) do
      Enum.flat_map(items, &extract_changes/1)
    else
      items
    end
  end

  defp has_changes_key?(%{} = item) do
    Map.has_key?(item, :changes) or Map.has_key?(item, "changes")
  end

  defp extract_changes(item) do
    case fetch_change_value(item, [:changes, "changes"]) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp changes_to_patch(changes) when is_list(changes) do
    changes
    |> Enum.reduce_while({:ok, []}, fn change, {:ok, acc} ->
      case change_to_patch(change) do
        {:ok, patch} -> {:cont, {:ok, [patch | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, patches} ->
        combined =
          patches
          |> Enum.reverse()
          |> Enum.join("\n")
          |> String.trim_trailing()
          |> ensure_trailing_newline()

        if combined == "\n", do: {:error, :empty_patch}, else: {:ok, combined}

      {:error, _} = error ->
        error
    end
  end

  defp changes_to_patch(_), do: {:error, :invalid_patch_changes}

  defp change_to_patch(change) when is_map(change) do
    with {:ok, path, kind, diff, move_path} <- normalize_change(change),
         true <- is_binary(diff) and String.trim(diff) != "" do
      if diff_has_headers?(diff) do
        {:ok, diff |> String.trim_trailing() |> ensure_trailing_newline()}
      else
        {old_path, new_path} = patch_paths(path, kind, move_path)
        header = patch_header(old_path, new_path)
        body = diff |> String.trim_trailing() |> ensure_trailing_newline()
        {:ok, header <> body}
      end
    else
      false -> {:error, {:missing_diff, change}}
      {:error, _} = error -> error
    end
  end

  defp change_to_patch(_), do: {:error, :invalid_patch_change}

  defp normalize_change(change) do
    path = fetch_change_value(change, [:path, "path"])
    diff = fetch_change_value(change, [:diff, "diff"])
    kind_value = fetch_change_value(change, [:kind, "kind"])
    move_path = fetch_change_value(change, [:move_path, "move_path", "movePath"])

    {kind, move_from_kind} = normalize_change_kind(kind_value)
    move_path = move_path || move_from_kind

    if not is_binary(path) or path == "" do
      {:error, {:invalid_change_path, change}}
    else
      {:ok, path, kind, diff, move_path}
    end
  end

  defp normalize_change_kind(%{} = kind) do
    move_path = fetch_change_value(kind, [:move_path, "move_path", "movePath"])
    type = fetch_change_value(kind, [:type, "type"])
    {kind_atom, _} = normalize_change_kind(type)
    {kind_atom, move_path}
  end

  defp normalize_change_kind(kind) when is_atom(kind) do
    {kind, nil}
  end

  defp normalize_change_kind(kind) when is_binary(kind) do
    case kind do
      "add" -> {:add, nil}
      "delete" -> {:delete, nil}
      "update" -> {:update, nil}
      _ -> {:update, nil}
    end
  end

  defp normalize_change_kind(_), do: {:update, nil}

  defp fetch_change_value(map, keys) when is_map(map) do
    Enum.find_value(keys, &Map.get(map, &1))
  end

  defp patch_paths(path, :add, _move_path), do: {"/dev/null", path}
  defp patch_paths(path, :delete, _move_path), do: {path, "/dev/null"}
  defp patch_paths(path, :update, move_path), do: {path, move_path || path}
  defp patch_paths(path, _kind, move_path), do: {path, move_path || path}

  defp patch_header(old_path, new_path) do
    [
      "diff --git ",
      format_patch_path(old_path, "a"),
      " ",
      format_patch_path(new_path, "b"),
      "\n",
      "--- ",
      format_patch_path(old_path, "a", true),
      "\n",
      "+++ ",
      format_patch_path(new_path, "b", true),
      "\n"
    ]
    |> IO.iodata_to_binary()
  end

  defp format_patch_path("/dev/null", _prefix), do: "/dev/null"

  defp format_patch_path(path, prefix) do
    "#{prefix}/#{path}"
  end

  defp format_patch_path("/dev/null", _prefix, _), do: "/dev/null"

  defp format_patch_path(path, prefix, _clean) do
    "#{prefix}/#{path}"
  end

  defp diff_has_headers?(diff) when is_binary(diff) do
    String.starts_with?(diff, "diff --git") or
      String.starts_with?(diff, "--- ") or
      String.contains?(diff, "\n--- ")
  end

  defp ensure_trailing_newline(text) when is_binary(text) do
    if String.ends_with?(text, "\n"), do: text, else: text <> "\n"
  end

  defp apply_patch(patch, opts) do
    timeout_ms = Keyword.get(opts, :timeout_ms, @default_apply_timeout_ms)
    cwd = Keyword.get(opts, :cwd, File.cwd!())
    args = apply_git_args(opts)

    with {:ok, git_path} <- resolve_git_path(),
         {:ok, stdout, stderr, exit_code} <-
           run_exec_command([git_path | args], patch, cwd, timeout_ms) do
      format_apply_result(stdout, stderr, exit_code)
    end
  end

  defp apply_git_args(opts) do
    if Keyword.get(opts, :preflight, Keyword.get(opts, :dry_run, false)) do
      ["apply", "--check"]
    else
      ["apply", "--3way"]
    end
  end

  defp resolve_git_path do
    case System.find_executable("git") do
      nil -> {:error, :git_not_found}
      git_path -> {:ok, git_path}
    end
  end

  defp format_apply_result(stdout, stderr, exit_code) do
    result = %{
      stdout: stdout,
      stderr: stderr,
      exit_code: exit_code,
      success: exit_code == 0
    }

    if exit_code == 0 do
      {:ok, result}
    else
      {:error, {:apply_failed, result}}
    end
  end

  defp run_exec_command(args, input, cwd, timeout_ms) do
    case ensure_erlexec_started() do
      :ok -> run_exec_command_inner(args, input, cwd, timeout_ms)
      {:error, reason} -> {:error, {:exec_start_failed, reason}}
    end
  end

  defp run_exec_command_inner(args, input, cwd, timeout_ms) do
    command = Enum.map(args, &to_charlist/1)

    opts =
      [:stdin, :stdout, :stderr, :monitor]
      |> maybe_add_cd(cwd)

    case :exec.run(command, opts) do
      {:ok, pid, os_pid} ->
        :ok = :exec.send(pid, input)
        :ok = :exec.send(pid, :eof)
        collect_output(pid, os_pid, timeout_ms, [], [])

      {:error, reason} ->
        {:error, {:exec_start_failed, reason}}
    end
  end

  defp maybe_add_cd(opts, nil), do: opts
  defp maybe_add_cd(opts, ""), do: opts
  defp maybe_add_cd(opts, cwd), do: [{:cd, to_charlist(cwd)} | opts]

  defp collect_output(pid, os_pid, timeout_ms, stdout_acc, stderr_acc) do
    receive do
      {:stdout, ^os_pid, data} ->
        collect_output(pid, os_pid, timeout_ms, [data | stdout_acc], stderr_acc)

      {:stderr, ^os_pid, data} ->
        collect_output(pid, os_pid, timeout_ms, stdout_acc, [data | stderr_acc])

      {:DOWN, ^os_pid, :process, _proc, reason} ->
        stdout = stdout_acc |> Enum.reverse() |> IO.iodata_to_binary()
        stderr = stderr_acc |> Enum.reverse() |> IO.iodata_to_binary()
        exit_code = normalize_exit_status(reason)
        {:ok, stdout, stderr, exit_code}
    after
      timeout_ms ->
        safe_stop(pid)
        {:error, :timeout}
    end
  end

  defp safe_stop(pid) do
    if Process.alive?(pid) do
      :exec.stop(pid)
    else
      :ok
    end
  rescue
    _ -> :ok
  end

  defp normalize_exit_status(:normal), do: 0

  defp normalize_exit_status({:exit_status, status}) when is_integer(status) do
    case :exec.status(status) do
      {:status, code} -> code
      {:signal, signal, _core?} -> 128 + signal_to_int(signal)
    end
  rescue
    _ -> status
  end

  defp normalize_exit_status(_), do: 1

  defp signal_to_int(signal) when is_integer(signal), do: signal

  defp signal_to_int(signal) when is_atom(signal) do
    :exec.signal_to_int(signal)
  rescue
    _ -> 1
  end

  defp ensure_erlexec_started do
    Erlexec.ensure_started()
  end

  defp normalize_ghost_commit(%Items.GhostSnapshot{ghost_commit: ghost_commit}),
    do: normalize_ghost_commit(ghost_commit)

  defp normalize_ghost_commit(%Items.RawResponseItem{type: "ghost_snapshot", payload: payload}),
    do: normalize_ghost_commit(payload)

  defp normalize_ghost_commit(%{"type" => "ghost_snapshot"} = item) do
    ghost_commit = Map.get(item, "ghost_commit") || Map.get(item, "ghostCommit")
    normalize_ghost_commit(ghost_commit || %{})
  end

  defp normalize_ghost_commit(%{} = ghost_commit) do
    case ghost_commit_id(ghost_commit) do
      nil -> {:error, :missing_ghost_commit_id}
      _id -> {:ok, ghost_commit}
    end
  end

  defp normalize_ghost_commit(_), do: {:error, :invalid_ghost_snapshot}

  defp ghost_commit_id(%{} = ghost_commit) do
    Map.get(ghost_commit, "id") || Map.get(ghost_commit, :id)
  end

  defp repo_root(cwd) do
    case System.cmd("git", ["rev-parse", "--show-toplevel"], cd: cwd, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, String.trim(output)}

      {output, status} ->
        {:error, {:not_a_git_repo, status, String.trim(output)}}
    end
  end

  defp repo_prefix(repo_root, cwd) do
    repo_root = Path.expand(repo_root)
    cwd = Path.expand(cwd)

    case Path.relative_to(cwd, repo_root) do
      "." -> {:ok, "."}
      rel -> {:ok, rel}
    end
  rescue
    _ -> {:ok, "."}
  end

  defp restore_git_snapshot(repo_root, prefix, ghost_commit) do
    commit_id = ghost_commit_id(ghost_commit)

    args = [
      "restore",
      "--source",
      commit_id,
      "--worktree",
      "--",
      prefix
    ]

    case System.cmd("git", args, cd: repo_root, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> {:error, {:git_restore_failed, status, String.trim(output)}}
    end
  end

  defp cleanup_untracked(repo_root, ghost_commit) do
    with {:ok, untracked} <- git_status_untracked(repo_root) do
      {preserve_files, preserve_dirs} = preexisting_paths(ghost_commit, repo_root)

      removed = remove_untracked(repo_root, untracked, preserve_files, preserve_dirs)

      {:ok, %{removed_paths: removed}}
    end
  end

  defp git_status_untracked(repo_root) do
    case System.cmd("git", ["status", "--porcelain=v1", "-uall"],
           cd: repo_root,
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        {:ok, parse_untracked_output(output)}

      {output, status} ->
        {:error, {:git_status_failed, status, String.trim(output)}}
    end
  end

  defp parse_untracked_output(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.flat_map(&parse_untracked_line/1)
  end

  defp remove_untracked(repo_root, untracked, preserve_files, preserve_dirs) do
    untracked
    |> Enum.reject(&preserve_path?(&1, preserve_files, preserve_dirs))
    |> Enum.reduce([], fn path, acc ->
      remove_untracked_path(repo_root, path, acc)
    end)
    |> Enum.reverse()
  end

  defp remove_untracked_path(repo_root, path, acc) do
    full = Path.join(repo_root, path)

    case File.rm_rf(full) do
      {:ok, _} -> [path | acc]
      {:error, _reason, _} -> acc
    end
  end

  defp parse_untracked_line("?? " <> path), do: [String.trim(path)]
  defp parse_untracked_line(_), do: []

  defp preexisting_paths(ghost_commit, repo_root) do
    files =
      ghost_commit
      |> fetch_change_value([
        "preexisting_untracked_files",
        "preexistingUntrackedFiles",
        :preexisting_untracked_files,
        :preexistingUntrackedFiles
      ])
      |> normalize_paths(repo_root)

    dirs =
      ghost_commit
      |> fetch_change_value([
        "preexisting_untracked_dirs",
        "preexistingUntrackedDirs",
        :preexisting_untracked_dirs,
        :preexistingUntrackedDirs
      ])
      |> normalize_paths(repo_root)

    {files, dirs}
  end

  defp normalize_paths(nil, _repo_root), do: []

  defp normalize_paths(paths, repo_root) when is_list(paths) do
    paths
    |> Enum.map(&normalize_path(&1, repo_root))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_paths(path, repo_root), do: normalize_paths([path], repo_root)

  defp normalize_path(path, repo_root) do
    path =
      case path do
        value when is_binary(value) -> value
        value when is_list(value) -> List.to_string(value)
        value -> to_string(value)
      end

    expanded = Path.expand(path, repo_root)

    case Path.relative_to(expanded, repo_root) do
      "." -> nil
      rel -> rel
    end
  rescue
    _ -> nil
  end

  defp preserve_path?(path, preserve_files, preserve_dirs) do
    path in preserve_files or
      Enum.any?(preserve_dirs, fn dir ->
        path == dir or String.starts_with?(path, dir <> "/")
      end)
  end
end
