defmodule Codex.Tools.ApplyPatchToolTest do
  use ExUnit.Case, async: true

  alias Codex.Tools.ApplyPatchTool

  @tmp_dir System.tmp_dir!()

  setup do
    test_dir = Path.join(@tmp_dir, "apply_patch_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(test_dir)
    on_exit(fn -> File.rm_rf!(test_dir) end)
    {:ok, test_dir: test_dir}
  end

  describe "metadata/0" do
    test "returns valid tool metadata" do
      meta = ApplyPatchTool.metadata()
      assert meta.name == "apply_patch"
      assert meta.description =~ "unified diff"
      assert meta.schema["type"] == "object"
      assert "patch" in meta.schema["required"]
    end
  end

  describe "parse_patch/1" do
    test "parses simple add patch" do
      patch = """
      --- /dev/null
      +++ b/new_file.txt
      @@ -0,0 +1,3 @@
      +line 1
      +line 2
      +line 3
      """

      {:ok, changes} = ApplyPatchTool.parse_patch(patch)
      assert length(changes) == 1
      {path, kind, hunks} = hd(changes)
      assert path == "new_file.txt"
      assert kind == :add
      assert length(hunks) == 1
    end

    test "parses delete patch" do
      patch = """
      --- a/old_file.txt
      +++ /dev/null
      @@ -1,2 +0,0 @@
      -line 1
      -line 2
      """

      {:ok, changes} = ApplyPatchTool.parse_patch(patch)
      assert length(changes) == 1
      {path, kind, _hunks} = hd(changes)
      assert path == "old_file.txt"
      assert kind == :delete
    end

    test "parses modify patch" do
      patch = """
      --- a/existing.txt
      +++ b/existing.txt
      @@ -1,3 +1,4 @@
       line 1
      -old line 2
      +new line 2
      +extra line
       line 3
      """

      {:ok, changes} = ApplyPatchTool.parse_patch(patch)
      assert length(changes) == 1
      {path, kind, hunks} = hd(changes)
      assert path == "existing.txt"
      assert kind == :modify
      assert length(hunks) == 1
    end

    test "parses multiple file changes" do
      patch = """
      --- /dev/null
      +++ b/file1.txt
      @@ -0,0 +1 @@
      +content 1
      --- a/file2.txt
      +++ b/file2.txt
      @@ -1 +1 @@
      -old
      +new
      """

      {:ok, changes} = ApplyPatchTool.parse_patch(patch)
      assert length(changes) == 2
    end

    test "handles empty patch" do
      {:ok, changes} = ApplyPatchTool.parse_patch("")
      assert changes == []
    end
  end

  describe "invoke/2 - create new file" do
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
      {:ok, result} = ApplyPatchTool.invoke(args, %{})

      assert result["applied"] == 1
      assert length(result["files"]) == 1
      assert hd(result["files"])["kind"] == "add"

      file_path = Path.join(dir, "new_file.txt")
      assert File.exists?(file_path)
      content = File.read!(file_path)
      assert content =~ "line 1"
      assert content =~ "line 2"
      assert content =~ "line 3"
    end

    test "creates nested directories as needed", %{test_dir: dir} do
      patch = """
      --- /dev/null
      +++ b/deep/nested/path/file.txt
      @@ -0,0 +1 @@
      +content
      """

      args = %{"patch" => patch, "base_path" => dir}
      {:ok, result} = ApplyPatchTool.invoke(args, %{})

      assert result["applied"] == 1
      file_path = Path.join(dir, "deep/nested/path/file.txt")
      assert File.exists?(file_path)
    end
  end

  describe "invoke/2 - delete file" do
    test "deletes file from patch", %{test_dir: dir} do
      file = Path.join(dir, "to_delete.txt")
      File.write!(file, "content\n")
      assert File.exists?(file)

      patch = """
      --- a/to_delete.txt
      +++ /dev/null
      @@ -1,1 +0,0 @@
      -content
      """

      args = %{"patch" => patch, "base_path" => dir}
      {:ok, result} = ApplyPatchTool.invoke(args, %{})

      assert result["applied"] == 1
      assert hd(result["files"])["kind"] == "delete"
      refute File.exists?(file)
    end

    test "returns error when deleting non-existent file", %{test_dir: dir} do
      patch = """
      --- a/nonexistent.txt
      +++ /dev/null
      @@ -1 +0,0 @@
      -content
      """

      args = %{"patch" => patch, "base_path" => dir}
      {:error, {_path, :enoent}} = ApplyPatchTool.invoke(args, %{})
    end
  end

  describe "invoke/2 - modify file" do
    test "modifies existing file", %{test_dir: dir} do
      file = Path.join(dir, "existing.txt")
      File.write!(file, "line 1\nold line 2\nline 3\n")

      patch = """
      --- a/existing.txt
      +++ b/existing.txt
      @@ -1,3 +1,4 @@
       line 1
      -old line 2
      +new line 2
      +extra line
       line 3
      """

      args = %{"patch" => patch, "base_path" => dir}
      {:ok, result} = ApplyPatchTool.invoke(args, %{})

      assert result["applied"] == 1
      content = File.read!(file)
      assert content =~ "new line 2"
      assert content =~ "extra line"
      refute content =~ "old line 2"
    end

    test "handles single line modification", %{test_dir: dir} do
      file = Path.join(dir, "single.txt")
      File.write!(file, "old content\n")

      patch = """
      --- a/single.txt
      +++ b/single.txt
      @@ -1 +1 @@
      -old content
      +new content
      """

      args = %{"patch" => patch, "base_path" => dir}
      {:ok, result} = ApplyPatchTool.invoke(args, %{})

      assert result["applied"] == 1
      content = File.read!(file)
      assert content =~ "new content"
    end
  end

  describe "invoke/2 - dry run" do
    test "dry run does not modify files", %{test_dir: dir} do
      patch = """
      --- /dev/null
      +++ b/should_not_exist.txt
      @@ -0,0 +1 @@
      +content
      """

      args = %{"patch" => patch, "base_path" => dir}
      {:ok, result} = ApplyPatchTool.invoke(args, %{dry_run: true})

      assert result["validated"] == 1
      assert result["applied"] == 0
      assert hd(result["files"])["dry_run"] == true
      refute File.exists?(Path.join(dir, "should_not_exist.txt"))
    end

    test "dry run via metadata", %{test_dir: dir} do
      patch = """
      --- /dev/null
      +++ b/should_not_exist.txt
      @@ -0,0 +1 @@
      +content
      """

      args = %{"patch" => patch, "base_path" => dir}
      context = %{metadata: %{dry_run: true}}
      {:ok, result} = ApplyPatchTool.invoke(args, context)

      assert result["validated"] == 1
      assert result["applied"] == 0
      refute File.exists?(Path.join(dir, "should_not_exist.txt"))
    end

    test "dry run validates existing file for delete", %{test_dir: dir} do
      file = Path.join(dir, "exists.txt")
      File.write!(file, "content")

      patch = """
      --- a/exists.txt
      +++ /dev/null
      @@ -1 +0,0 @@
      -content
      """

      args = %{"patch" => patch, "base_path" => dir}
      {:ok, result} = ApplyPatchTool.invoke(args, %{dry_run: true})

      assert result["validated"] == 1
      assert File.exists?(file)
    end
  end

  describe "invoke/2 - approval" do
    test "respects approval callback - approved", %{test_dir: dir} do
      patch = """
      --- /dev/null
      +++ b/approved.txt
      @@ -0,0 +1 @@
      +content
      """

      args = %{"patch" => patch, "base_path" => dir}
      context = %{metadata: %{approval: fn _changes, _ctx -> :ok end}}
      {:ok, result} = ApplyPatchTool.invoke(args, context)

      assert result["applied"] == 1
      assert File.exists?(Path.join(dir, "approved.txt"))
    end

    test "respects approval callback - denied", %{test_dir: dir} do
      patch = """
      --- /dev/null
      +++ b/denied.txt
      @@ -0,0 +1 @@
      +content
      """

      args = %{"patch" => patch, "base_path" => dir}
      context = %{metadata: %{approval: fn _changes, _ctx -> {:deny, "not allowed"} end}}

      assert {:deny, "not allowed"} = ApplyPatchTool.invoke(args, context)
      refute File.exists?(Path.join(dir, "denied.txt"))
    end

    test "approval callback receives change summary", %{test_dir: dir} do
      patch = """
      --- /dev/null
      +++ b/new.txt
      @@ -0,0 +1,3 @@
      +line 1
      +line 2
      +line 3
      """

      test_pid = self()

      args = %{"patch" => patch, "base_path" => dir}

      context = %{
        metadata: %{
          approval: fn changes, _ctx ->
            send(test_pid, {:changes, changes})
            :ok
          end
        }
      }

      {:ok, _result} = ApplyPatchTool.invoke(args, context)

      assert_receive {:changes, changes}
      assert length(changes) == 1
      change = hd(changes)
      assert change.path == "new.txt"
      assert change.kind == :add
      assert change.additions == 3
      assert change.deletions == 0
    end

    test "approval with :deny atom", %{test_dir: dir} do
      patch = """
      --- /dev/null
      +++ b/denied.txt
      @@ -0,0 +1 @@
      +content
      """

      args = %{"patch" => patch, "base_path" => dir}
      context = %{metadata: %{approval: fn _changes, _ctx -> :deny end}}

      assert {:deny, :denied} = ApplyPatchTool.invoke(args, context)
    end

    test "approval with false", %{test_dir: dir} do
      patch = """
      --- /dev/null
      +++ b/denied.txt
      @@ -0,0 +1 @@
      +content
      """

      args = %{"patch" => patch, "base_path" => dir}
      context = %{metadata: %{approval: fn _changes, _ctx -> false end}}

      assert {:deny, :denied} = ApplyPatchTool.invoke(args, context)
    end
  end

  describe "invoke/2 - error handling" do
    test "returns error for missing patch" do
      {:error, {:missing_argument, :patch}} = ApplyPatchTool.invoke(%{}, %{})
    end

    test "returns error for empty patch" do
      {:error, {:empty_patch, _}} = ApplyPatchTool.invoke(%{"patch" => ""}, %{})
    end

    test "returns error for invalid patch type" do
      {:error, {:invalid_argument, :patch}} = ApplyPatchTool.invoke(%{"patch" => 123}, %{})
    end

    test "returns error when modifying non-existent file", %{test_dir: dir} do
      patch = """
      --- a/nonexistent.txt
      +++ b/nonexistent.txt
      @@ -1 +1 @@
      -old
      +new
      """

      args = %{"patch" => patch, "base_path" => dir}
      {:error, {"nonexistent.txt", :enoent}} = ApplyPatchTool.invoke(args, %{})
    end
  end

  describe "invoke/2 - base_path handling" do
    test "uses base_path from args", %{test_dir: dir} do
      patch = """
      --- /dev/null
      +++ b/file.txt
      @@ -0,0 +1 @@
      +content
      """

      args = %{"patch" => patch, "base_path" => dir}
      {:ok, _result} = ApplyPatchTool.invoke(args, %{})

      assert File.exists?(Path.join(dir, "file.txt"))
    end

    test "uses base_path from context", %{test_dir: dir} do
      patch = """
      --- /dev/null
      +++ b/file.txt
      @@ -0,0 +1 @@
      +content
      """

      args = %{"patch" => patch}
      {:ok, _result} = ApplyPatchTool.invoke(args, %{base_path: dir})

      assert File.exists?(Path.join(dir, "file.txt"))
    end

    test "uses base_path from metadata", %{test_dir: dir} do
      patch = """
      --- /dev/null
      +++ b/file.txt
      @@ -0,0 +1 @@
      +content
      """

      args = %{"patch" => patch}
      context = %{metadata: %{base_path: dir}}
      {:ok, _result} = ApplyPatchTool.invoke(args, context)

      assert File.exists?(Path.join(dir, "file.txt"))
    end

    test "args base_path takes precedence", %{test_dir: dir} do
      other_dir = Path.join(@tmp_dir, "other_#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(other_dir)
      on_exit(fn -> File.rm_rf!(other_dir) end)

      patch = """
      --- /dev/null
      +++ b/file.txt
      @@ -0,0 +1 @@
      +content
      """

      args = %{"patch" => patch, "base_path" => dir}
      context = %{base_path: other_dir}
      {:ok, _result} = ApplyPatchTool.invoke(args, context)

      assert File.exists?(Path.join(dir, "file.txt"))
      refute File.exists?(Path.join(other_dir, "file.txt"))
    end
  end

  describe "apply_hunks/2" do
    test "applies simple modification" do
      content = "line 1\nold line\nline 3"

      hunks = [
        %{
          old_start: 1,
          old_count: 3,
          new_start: 1,
          new_count: 3,
          lines: [
            {:context, "line 1"},
            {:remove, "old line"},
            {:add, "new line"},
            {:context, "line 3"}
          ]
        }
      ]

      {:ok, result} = ApplyPatchTool.apply_hunks(content, hunks)
      assert result =~ "new line"
      refute result =~ "old line"
    end

    test "applies addition at end" do
      content = "line 1\nline 2"

      hunks = [
        %{
          old_start: 1,
          old_count: 2,
          new_start: 1,
          new_count: 3,
          lines: [
            {:context, "line 1"},
            {:context, "line 2"},
            {:add, "line 3"}
          ]
        }
      ]

      {:ok, result} = ApplyPatchTool.apply_hunks(content, hunks)
      assert result =~ "line 3"
    end

    test "applies deletion" do
      content = "line 1\nto delete\nline 3"

      hunks = [
        %{
          old_start: 1,
          old_count: 3,
          new_start: 1,
          new_count: 2,
          lines: [
            {:context, "line 1"},
            {:remove, "to delete"},
            {:context, "line 3"}
          ]
        }
      ]

      {:ok, result} = ApplyPatchTool.apply_hunks(content, hunks)
      refute result =~ "to delete"
      assert result =~ "line 1"
      assert result =~ "line 3"
    end
  end
end
