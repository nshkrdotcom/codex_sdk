defmodule Codex.SessionsTest do
  use ExUnit.Case, async: false

  alias Codex.Items
  alias Codex.Sessions

  test "list_sessions preserves unknown metadata" do
    sessions_dir =
      Path.join(System.tmp_dir!(), "codex_sessions_#{System.unique_integer([:positive])}")

    File.mkdir_p!(sessions_dir)

    session_path = Path.join(sessions_dir, "session.jsonl")

    payload = %{
      "id" => "thread_1",
      "timestamp" => "2025-01-01T00:00:00Z",
      "cwd" => "/tmp",
      "originator" => "cli",
      "cli_version" => "0.0.0",
      "extra_payload" => "keep_me"
    }

    raw = %{
      "type" => "session",
      "payload" => payload,
      "extra_raw" => "keep_raw"
    }

    File.write!(session_path, Jason.encode!(raw) <> "\n")

    on_exit(fn -> File.rm_rf(sessions_dir) end)

    assert {:ok, [entry]} = Sessions.list_sessions(sessions_dir: sessions_dir)
    assert entry.id == "thread_1"
    assert entry.metadata["extra_payload"] == "keep_me"
    assert entry.metadata["extra_raw"] == "keep_raw"
  end

  test "list_sessions handles empty session files" do
    sessions_dir =
      Path.join(System.tmp_dir!(), "codex_sessions_#{System.unique_integer([:positive])}")

    File.mkdir_p!(sessions_dir)

    session_path = Path.join(sessions_dir, "empty.jsonl")
    File.write!(session_path, "")

    on_exit(fn -> File.rm_rf(sessions_dir) end)

    assert {:ok, [entry]} = Sessions.list_sessions(sessions_dir: sessions_dir)
    assert entry.id == "empty"
    assert entry.metadata == %{}
    assert entry.started_at == nil
  end

  test "apply/2 applies unified diffs" do
    {repo_path, file_path} = init_repo_with_file("one\n")

    File.write!(file_path, "two\n")
    diff = git!(repo_path, ["diff"])

    git!(repo_path, ["restore", "--worktree", "--", Path.basename(file_path)])
    assert File.read!(file_path) == "one\n"

    assert {:ok, result} = Sessions.apply(diff, cwd: repo_path)
    assert result.success == true
    assert File.read!(file_path) == "two\n"
  end

  test "apply/2 builds patches from file change items" do
    {repo_path, file_path} = init_repo_with_file("alpha\n")

    diff_body = "@@ -1 +1 @@\n-alpha\n+beta\n"

    change = %{
      path: Path.basename(file_path),
      kind: :update,
      diff: diff_body
    }

    item = %Items.FileChange{changes: [change], status: :completed}

    assert {:ok, result} = Sessions.apply([item], cwd: repo_path)
    assert result.success == true
    assert File.read!(file_path) == "beta\n"
  end

  test "undo/2 restores ghost snapshot commits and cleans untracked files" do
    {repo_path, file_path} = init_repo_with_file("before\n")

    keep_path = Path.join(repo_path, "keep.txt")
    remove_path = Path.join(repo_path, "remove.txt")

    File.write!(keep_path, "keep\n")

    commit_id = git!(repo_path, ["rev-parse", "HEAD"]) |> String.trim()

    File.write!(file_path, "after\n")
    File.write!(remove_path, "remove\n")

    snapshot = %Items.GhostSnapshot{
      ghost_commit: %{
        "id" => commit_id,
        "preexisting_untracked_files" => ["keep.txt"],
        "preexisting_untracked_dirs" => []
      }
    }

    assert {:ok, %{removed_paths: removed}} = Sessions.undo(snapshot, cwd: repo_path)
    assert File.read!(file_path) == "before\n"
    assert File.exists?(keep_path)
    refute File.exists?(remove_path)
    assert "remove.txt" in removed
  end

  defp init_repo_with_file(contents) do
    repo_path =
      Path.join(System.tmp_dir!(), "codex_repo_#{System.unique_integer([:positive])}")

    File.mkdir_p!(repo_path)
    on_exit(fn -> File.rm_rf(repo_path) end)
    git!(repo_path, ["init"])
    git!(repo_path, ["config", "user.email", "test@example.com"])
    git!(repo_path, ["config", "user.name", "Codex SDK"])

    file_path = Path.join(repo_path, "note.txt")
    File.write!(file_path, contents)

    git!(repo_path, ["add", Path.basename(file_path)])
    git!(repo_path, ["commit", "-m", "initial"])

    {repo_path, file_path}
  end

  defp git!(repo_path, args) do
    {output, status} = System.cmd("git", args, cd: repo_path, stderr_to_stdout: true)

    if status == 0 do
      output
    else
      raise "git #{Enum.join(args, " ")} failed: #{output}"
    end
  end
end
