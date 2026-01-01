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
      assert meta.description =~ "apply_patch"
      assert meta.schema["type"] == "object"
      assert meta.schema["additionalProperties"] == false
      assert meta.schema["properties"]["input"]["type"] == "string"
      assert meta.schema["properties"]["patch"]["type"] == "string"
    end
  end

  describe "parse_patch/1" do
    test "parses apply_patch add file" do
      patch = """
      *** Begin Patch
      *** Add File: new_file.txt
      +line 1
      +line 2
      +line 3
      *** End Patch
      """

      {:ok, changes} = ApplyPatchTool.parse_patch(patch)
      assert length(changes) == 1
      change = hd(changes)
      assert change.format == :apply_patch
      assert change.kind == :add
      assert change.path == "new_file.txt"
      assert change.content == ["line 1", "line 2", "line 3"]
    end

    test "parses apply_patch delete file" do
      patch = """
      *** Begin Patch
      *** Delete File: old_file.txt
      *** End Patch
      """

      {:ok, changes} = ApplyPatchTool.parse_patch(patch)
      assert length(changes) == 1
      change = hd(changes)
      assert change.format == :apply_patch
      assert change.kind == :delete
      assert change.path == "old_file.txt"
    end

    test "parses apply_patch update file" do
      patch = """
      *** Begin Patch
      *** Update File: existing.txt
      @@
       line 1
      -old line 2
      +new line 2
       line 3
      *** End Patch
      """

      {:ok, changes} = ApplyPatchTool.parse_patch(patch)
      assert length(changes) == 1
      change = hd(changes)
      assert change.format == :apply_patch
      assert change.kind == :update
      assert change.path == "existing.txt"
      assert Enum.any?(change.segments, &match?({:chunk, _}, &1))
    end

    test "parses unified diff fallback" do
      patch = """
      --- a/existing.txt
      +++ b/existing.txt
      @@ -1,3 +1,3 @@
       line 1
      -old line 2
      +new line 2
       line 3
      """

      {:ok, changes} = ApplyPatchTool.parse_patch(patch)
      assert length(changes) == 1
      change = hd(changes)
      assert change.format == :unified_diff
      assert change.kind == :update
      assert change.path == "existing.txt"
      assert length(change.hunks) == 1
    end

    test "handles empty patch" do
      {:ok, changes} = ApplyPatchTool.parse_patch("")
      assert changes == []
    end
  end

  describe "invoke/2 - create new file" do
    test "creates new file from patch", %{test_dir: dir} do
      patch = """
      *** Begin Patch
      *** Add File: new_file.txt
      +line 1
      +line 2
      +line 3
      *** End Patch
      """

      args = %{"input" => patch, "base_path" => dir}
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
      *** Begin Patch
      *** Add File: deep/nested/path/file.txt
      +content
      *** End Patch
      """

      args = %{"input" => patch, "base_path" => dir}
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
      *** Begin Patch
      *** Delete File: to_delete.txt
      *** End Patch
      """

      args = %{"input" => patch, "base_path" => dir}
      {:ok, result} = ApplyPatchTool.invoke(args, %{})

      assert result["applied"] == 1
      assert hd(result["files"])["kind"] == "delete"
      refute File.exists?(file)
    end

    test "returns error when deleting non-existent file", %{test_dir: dir} do
      patch = """
      *** Begin Patch
      *** Delete File: nonexistent.txt
      *** End Patch
      """

      args = %{"input" => patch, "base_path" => dir}
      {:error, {_path, :enoent}} = ApplyPatchTool.invoke(args, %{})
    end
  end

  describe "invoke/2 - modify file" do
    test "modifies existing file", %{test_dir: dir} do
      file = Path.join(dir, "existing.txt")
      File.write!(file, "line 1\nold line 2\nline 3\n")

      patch = """
      *** Begin Patch
      *** Update File: existing.txt
      @@
       line 1
      -old line 2
      +new line 2
      +extra line
       line 3
      *** End Patch
      """

      args = %{"input" => patch, "base_path" => dir}
      {:ok, result} = ApplyPatchTool.invoke(args, %{})

      assert result["applied"] == 1
      content = File.read!(file)
      assert content =~ "new line 2"
      assert content =~ "extra line"
      refute content =~ "old line 2"
    end

    test "renames file with move_to", %{test_dir: dir} do
      file = Path.join(dir, "old_name.txt")
      File.write!(file, "hello\n")

      patch = """
      *** Begin Patch
      *** Update File: old_name.txt
      *** Move to: new_name.txt
      *** End Patch
      """

      args = %{"input" => patch, "base_path" => dir}
      {:ok, result} = ApplyPatchTool.invoke(args, %{})

      assert result["applied"] == 1
      assert hd(result["files"])["move_path"] == Path.join(dir, "new_name.txt")
      refute File.exists?(file)
      assert File.read!(Path.join(dir, "new_name.txt")) == "hello\n"
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
      *** Begin Patch
      *** Add File: should_not_exist.txt
      +content
      *** End Patch
      """

      args = %{"input" => patch, "base_path" => dir}
      {:ok, result} = ApplyPatchTool.invoke(args, %{dry_run: true})

      assert result["validated"] == 1
      assert result["applied"] == 0
      assert hd(result["files"])["dry_run"] == true
      refute File.exists?(Path.join(dir, "should_not_exist.txt"))
    end

    test "dry run via metadata", %{test_dir: dir} do
      patch = """
      *** Begin Patch
      *** Add File: should_not_exist.txt
      +content
      *** End Patch
      """

      args = %{"input" => patch, "base_path" => dir}
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
      *** Begin Patch
      *** Delete File: exists.txt
      *** End Patch
      """

      args = %{"input" => patch, "base_path" => dir}
      {:ok, result} = ApplyPatchTool.invoke(args, %{dry_run: true})

      assert result["validated"] == 1
      assert File.exists?(file)
    end
  end

  describe "invoke/2 - approval" do
    test "respects approval callback - approved", %{test_dir: dir} do
      patch = """
      *** Begin Patch
      *** Add File: approved.txt
      +content
      *** End Patch
      """

      args = %{"input" => patch, "base_path" => dir}
      context = %{metadata: %{approval: fn _changes, _ctx -> :ok end}}
      {:ok, result} = ApplyPatchTool.invoke(args, context)

      assert result["applied"] == 1
      assert File.exists?(Path.join(dir, "approved.txt"))
    end

    test "respects approval callback - denied", %{test_dir: dir} do
      patch = """
      *** Begin Patch
      *** Add File: denied.txt
      +content
      *** End Patch
      """

      args = %{"input" => patch, "base_path" => dir}
      context = %{metadata: %{approval: fn _changes, _ctx -> {:deny, "not allowed"} end}}

      assert {:deny, "not allowed"} = ApplyPatchTool.invoke(args, context)
      refute File.exists?(Path.join(dir, "denied.txt"))
    end

    test "approval callback receives change summary", %{test_dir: dir} do
      patch = """
      *** Begin Patch
      *** Add File: new.txt
      +line 1
      +line 2
      +line 3
      *** End Patch
      """

      test_pid = self()

      args = %{"input" => patch, "base_path" => dir}

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
      *** Begin Patch
      *** Add File: denied.txt
      +content
      *** End Patch
      """

      args = %{"input" => patch, "base_path" => dir}
      context = %{metadata: %{approval: fn _changes, _ctx -> :deny end}}

      assert {:deny, :denied} = ApplyPatchTool.invoke(args, context)
    end

    test "approval with false", %{test_dir: dir} do
      patch = """
      *** Begin Patch
      *** Add File: denied.txt
      +content
      *** End Patch
      """

      args = %{"input" => patch, "base_path" => dir}
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
      *** Begin Patch
      *** Update File: nonexistent.txt
      @@
      -old
      +new
      *** End Patch
      """

      args = %{"input" => patch, "base_path" => dir}
      {:error, {"nonexistent.txt", :enoent}} = ApplyPatchTool.invoke(args, %{})
    end
  end

  describe "invoke/2 - base_path handling" do
    test "uses base_path from args", %{test_dir: dir} do
      patch = """
      *** Begin Patch
      *** Add File: file.txt
      +content
      *** End Patch
      """

      args = %{"input" => patch, "base_path" => dir}
      {:ok, _result} = ApplyPatchTool.invoke(args, %{})

      assert File.exists?(Path.join(dir, "file.txt"))
    end

    test "uses base_path from context", %{test_dir: dir} do
      patch = """
      *** Begin Patch
      *** Add File: file.txt
      +content
      *** End Patch
      """

      args = %{"input" => patch}
      {:ok, _result} = ApplyPatchTool.invoke(args, %{base_path: dir})

      assert File.exists?(Path.join(dir, "file.txt"))
    end

    test "uses base_path from metadata", %{test_dir: dir} do
      patch = """
      *** Begin Patch
      *** Add File: file.txt
      +content
      *** End Patch
      """

      args = %{"input" => patch}
      context = %{metadata: %{base_path: dir}}
      {:ok, _result} = ApplyPatchTool.invoke(args, context)

      assert File.exists?(Path.join(dir, "file.txt"))
    end

    test "args base_path takes precedence", %{test_dir: dir} do
      other_dir = Path.join(@tmp_dir, "other_#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(other_dir)
      on_exit(fn -> File.rm_rf!(other_dir) end)

      patch = """
      *** Begin Patch
      *** Add File: file.txt
      +content
      *** End Patch
      """

      args = %{"input" => patch, "base_path" => dir}
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
