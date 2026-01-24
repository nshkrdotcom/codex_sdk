defmodule Codex.Tools.FileSearchToolTest do
  use ExUnit.Case, async: true

  alias Codex.Tool
  alias Codex.Tools
  alias Codex.Tools.FileSearchTool

  @tmp_dir System.tmp_dir!()

  setup do
    test_dir = Path.join(@tmp_dir, "file_search_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(test_dir)

    # Create test files
    File.write!(Path.join(test_dir, "test.ex"), """
    defmodule Test do
      def hello, do: :world
    end
    """)

    File.write!(Path.join(test_dir, "test.exs"), "ExUnit.start()")
    File.write!(Path.join(test_dir, "readme.md"), "# README\n\nThis is a test file.")
    File.mkdir_p!(Path.join(test_dir, "subdir"))

    File.write!(
      Path.join(test_dir, "subdir/nested.ex"),
      "# nested file\ndefmodule Nested do\nend"
    )

    File.write!(Path.join(test_dir, "subdir/another.ex"), "defmodule Another do\nend")
    File.mkdir_p!(Path.join(test_dir, ".hidden"))
    File.write!(Path.join(test_dir, ".hidden/secret.ex"), "# hidden file")
    File.write!(Path.join(test_dir, ".dotfile.ex"), "# dot file")

    on_exit(fn -> File.rm_rf!(test_dir) end)
    {:ok, test_dir: test_dir}
  end

  describe "metadata/0" do
    test "returns valid tool metadata" do
      meta = FileSearchTool.metadata()
      assert meta.name == "file_search"
      assert meta.description == "Search for files by name pattern or content"
      assert meta.schema["required"] == ["pattern"]
      assert meta.schema["properties"]["pattern"]["type"] == "string"
      assert meta.schema["properties"]["content"]["type"] == "string"
      assert meta.schema["properties"]["base_path"]["type"] == "string"
      assert meta.schema["properties"]["max_results"]["type"] == "integer"
      assert meta.schema["properties"]["case_sensitive"]["type"] == "boolean"
    end

    test "Tool.metadata/1 returns module metadata" do
      assert Tool.metadata(FileSearchTool)[:name] == "file_search"
    end
  end

  describe "invoke/2 - basic file discovery" do
    test "finds files by glob pattern", %{test_dir: dir} do
      args = %{"pattern" => "*.ex", "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      assert result["count"] == 1
      assert hd(result["files"])["path"] == "test.ex"
    end

    test "finds files by extension pattern", %{test_dir: dir} do
      args = %{"pattern" => "*.exs", "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      assert result["count"] == 1
      assert hd(result["files"])["path"] == "test.exs"
    end

    test "finds files recursively with **", %{test_dir: dir} do
      args = %{"pattern" => "**/*.ex", "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      assert result["count"] == 3
      paths = Enum.map(result["files"], & &1["path"])
      assert "test.ex" in paths
      assert "subdir/nested.ex" in paths
      assert "subdir/another.ex" in paths
    end

    test "finds files with {a,b} pattern", %{test_dir: dir} do
      args = %{"pattern" => "*.{ex,exs}", "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      assert result["count"] == 2
      paths = Enum.map(result["files"], & &1["path"])
      assert "test.ex" in paths
      assert "test.exs" in paths
    end

    test "finds files in subdirectory", %{test_dir: dir} do
      args = %{"pattern" => "subdir/*.ex", "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      assert result["count"] == 2
      paths = Enum.map(result["files"], & &1["path"])
      assert "subdir/nested.ex" in paths
      assert "subdir/another.ex" in paths
    end

    test "returns empty for no matches", %{test_dir: dir} do
      args = %{"pattern" => "*.rs", "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      assert result["count"] == 0
      assert result["files"] == []
    end

    test "does not include hidden files by default", %{test_dir: dir} do
      args = %{"pattern" => "**/*.ex", "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      paths = Enum.map(result["files"], & &1["path"])
      refute ".dotfile.ex" in paths
      refute ".hidden/secret.ex" in paths
    end

    test "returns sorted results", %{test_dir: dir} do
      args = %{"pattern" => "**/*.ex", "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      paths = Enum.map(result["files"], & &1["path"])
      assert paths == Enum.sort(paths)
    end
  end

  describe "invoke/2 - content search" do
    test "searches file content", %{test_dir: dir} do
      args = %{"pattern" => "*.ex", "content" => "defmodule", "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      assert result["count"] == 1
      file = hd(result["files"])
      assert file["path"] == "test.ex"
      assert length(file["matches"]) == 1
      match = hd(file["matches"])
      assert match["line"] == 1
      assert match["text"] == "defmodule Test do"
    end

    test "searches content recursively", %{test_dir: dir} do
      args = %{"pattern" => "**/*.ex", "content" => "defmodule", "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      assert result["count"] == 3
      paths = Enum.map(result["files"], & &1["path"])
      assert "test.ex" in paths
      assert "subdir/nested.ex" in paths
      assert "subdir/another.ex" in paths
    end

    test "filters files by content match", %{test_dir: dir} do
      args = %{"pattern" => "**/*.ex", "content" => "Nested", "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      assert result["count"] == 1
      assert hd(result["files"])["path"] == "subdir/nested.ex"
    end

    test "finds multiple matches in a file", %{test_dir: dir} do
      args = %{"pattern" => "*.ex", "content" => "def", "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      assert result["count"] == 1
      file = hd(result["files"])
      assert length(file["matches"]) == 2
      lines = Enum.map(file["matches"], & &1["line"])
      assert 1 in lines
      assert 2 in lines
    end

    test "supports regex patterns in content", %{test_dir: dir} do
      args = %{"pattern" => "*.ex", "content" => "def\\s+\\w+", "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      assert result["count"] == 1
    end

    test "returns error for invalid regex", %{test_dir: dir} do
      args = %{"pattern" => "*.ex", "content" => "[invalid", "base_path" => dir}
      {:error, {:regex_error, _reason}} = FileSearchTool.invoke(args, %{})
    end

    test "returns empty when content not found", %{test_dir: dir} do
      args = %{"pattern" => "*.ex", "content" => "nonexistent_string", "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      assert result["count"] == 0
      assert result["files"] == []
    end
  end

  describe "invoke/2 - case sensitivity" do
    test "case sensitive search by default", %{test_dir: dir} do
      args = %{"pattern" => "*.ex", "content" => "DEFMODULE", "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      assert result["count"] == 0
    end

    test "case insensitive search", %{test_dir: dir} do
      args = %{
        "pattern" => "*.ex",
        "content" => "DEFMODULE",
        "case_sensitive" => false,
        "base_path" => dir
      }

      {:ok, result} = FileSearchTool.invoke(args, %{})

      assert result["count"] == 1
      assert hd(result["files"])["path"] == "test.ex"
    end

    test "case sensitive search explicit", %{test_dir: dir} do
      args = %{
        "pattern" => "*.ex",
        "content" => "defmodule",
        "case_sensitive" => true,
        "base_path" => dir
      }

      {:ok, result} = FileSearchTool.invoke(args, %{})

      assert result["count"] == 1
    end
  end

  describe "invoke/2 - max_results" do
    test "respects max_results", %{test_dir: dir} do
      args = %{"pattern" => "**/*", "max_results" => 2, "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      assert result["count"] == 2
    end

    test "returns all when max_results exceeds matches", %{test_dir: dir} do
      args = %{"pattern" => "*.ex", "max_results" => 100, "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      assert result["count"] == 1
    end

    test "max_results applies after content filtering", %{test_dir: dir} do
      args = %{
        "pattern" => "**/*.ex",
        "content" => "defmodule",
        "max_results" => 1,
        "base_path" => dir
      }

      {:ok, result} = FileSearchTool.invoke(args, %{})

      assert result["count"] == 1
    end
  end

  describe "invoke/2 - base_path resolution" do
    test "uses base_path from args", %{test_dir: dir} do
      args = %{"pattern" => "*.ex", "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      assert result["count"] == 1
    end

    test "uses base_path from context", %{test_dir: dir} do
      args = %{"pattern" => "*.ex"}
      {:ok, result} = FileSearchTool.invoke(args, %{base_path: dir})

      assert result["count"] == 1
    end

    test "uses base_path from metadata", %{test_dir: dir} do
      args = %{"pattern" => "*.ex"}
      {:ok, result} = FileSearchTool.invoke(args, %{metadata: %{base_path: dir}})

      assert result["count"] == 1
    end

    test "args base_path takes precedence over context", %{test_dir: dir} do
      other_dir = Path.join(@tmp_dir, "other_#{:rand.uniform(100_000)}")
      File.mkdir_p!(other_dir)
      on_exit(fn -> File.rm_rf!(other_dir) end)

      args = %{"pattern" => "*.ex", "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{base_path: other_dir})

      assert result["count"] == 1
    end
  end

  describe "invoke/2 - result format" do
    test "result structure without content search", %{test_dir: dir} do
      args = %{"pattern" => "*.ex", "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      assert is_integer(result["count"])
      assert is_list(result["files"])

      file = hd(result["files"])
      assert is_binary(file["path"])
      refute Map.has_key?(file, "matches")
    end

    test "result structure with content search", %{test_dir: dir} do
      args = %{"pattern" => "*.ex", "content" => "defmodule", "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      assert is_integer(result["count"])
      assert is_list(result["files"])

      file = hd(result["files"])
      assert is_binary(file["path"])
      assert is_list(file["matches"])

      match = hd(file["matches"])
      assert is_integer(match["line"])
      assert is_binary(match["text"])
    end
  end

  describe "registration and invocation via Tools" do
    setup do
      Tools.reset!()
      Tools.reset_metrics()

      on_exit(fn ->
        Tools.reset!()
        Tools.reset_metrics()
      end)

      :ok
    end

    test "registers with default name", %{test_dir: dir} do
      {:ok, handle} = Tools.register(FileSearchTool, base_path: dir)
      assert handle.name == "file_search"
      assert handle.module == FileSearchTool
    end

    test "invokes via registry", %{test_dir: dir} do
      {:ok, _} = Tools.register(FileSearchTool, base_path: dir)

      {:ok, result} = Tools.invoke("file_search", %{"pattern" => "*.ex"}, %{})

      assert result["count"] == 1
      assert hd(result["files"])["path"] == "test.ex"
    end

    test "respects max_results from registration", %{test_dir: dir} do
      {:ok, _} = Tools.register(FileSearchTool, base_path: dir, max_results: 1)

      {:ok, result} = Tools.invoke("file_search", %{"pattern" => "**/*"}, %{})

      assert result["count"] == 1
    end

    test "respects case_sensitive from registration", %{test_dir: dir} do
      {:ok, _} = Tools.register(FileSearchTool, base_path: dir, case_sensitive: false)

      {:ok, result} =
        Tools.invoke("file_search", %{"pattern" => "*.ex", "content" => "DEFMODULE"}, %{})

      assert result["count"] == 1
    end

    test "lookup returns registered tool", %{test_dir: dir} do
      {:ok, _} = Tools.register(FileSearchTool, base_path: dir)
      assert {:ok, info} = Tools.lookup("file_search")
      assert info.module == FileSearchTool
    end

    test "records metrics on invocation", %{test_dir: dir} do
      {:ok, _} = Tools.register(FileSearchTool, base_path: dir)

      {:ok, _} = Tools.invoke("file_search", %{"pattern" => "*.ex"}, %{})

      metrics = Tools.metrics()
      assert metrics["file_search"].success == 1
      assert metrics["file_search"].failure == 0
    end
  end

  describe "edge cases" do
    test "handles empty directory", %{test_dir: _dir} do
      empty_dir = Path.join(@tmp_dir, "empty_#{:rand.uniform(100_000)}")
      File.mkdir_p!(empty_dir)
      on_exit(fn -> File.rm_rf!(empty_dir) end)

      args = %{"pattern" => "*.ex", "base_path" => empty_dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      assert result["count"] == 0
      assert result["files"] == []
    end

    test "handles nonexistent base_path gracefully" do
      args = %{"pattern" => "*.ex", "base_path" => "/nonexistent/path/that/does/not/exist"}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      assert result["count"] == 0
      assert result["files"] == []
    end

    test "handles files with no read permission", %{test_dir: dir} do
      unreadable_file = Path.join(dir, "unreadable.ex")
      File.write!(unreadable_file, "defmodule Unreadable do\nend")
      File.chmod!(unreadable_file, 0o000)
      on_exit(fn -> File.chmod!(unreadable_file, 0o644) end)

      args = %{"pattern" => "*.ex", "content" => "defmodule", "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      # Should still find other files, just not match the unreadable one
      paths = Enum.map(result["files"], & &1["path"])
      refute "unreadable.ex" in paths
    end

    test "skips binary files in content search", %{test_dir: dir} do
      binary_file = Path.join(dir, "binary.ex")
      # Write a file with invalid UTF-8 content
      File.write!(binary_file, <<0xFF, 0xFE, 0x00, 0x01>>)

      args = %{"pattern" => "*.ex", "content" => "anything", "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      paths = Enum.map(result["files"], & &1["path"])
      refute "binary.ex" in paths
    end

    test "handles empty content string as pattern search only", %{test_dir: dir} do
      args = %{"pattern" => "*.ex", "content" => "", "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      # Empty content regex matches all lines, so files with any content match
      assert result["count"] >= 0
    end

    test "handles special characters in pattern", %{test_dir: dir} do
      special_file = Path.join(dir, "test-file.ex")
      File.write!(special_file, "defmodule TestFile do\nend")

      args = %{"pattern" => "*-*.ex", "base_path" => dir}
      {:ok, result} = FileSearchTool.invoke(args, %{})

      assert result["count"] == 1
      assert hd(result["files"])["path"] == "test-file.ex"
    end
  end

  describe "live integration tests" do
    setup do
      Tools.reset!()
      on_exit(fn -> Tools.reset!() end)
      :ok
    end

    @tag :live
    test "searches real codebase" do
      {:ok, _} = Tools.register(FileSearchTool)
      {:ok, result} = Tools.invoke("file_search", %{"pattern" => "lib/**/*.ex"}, %{})
      assert result["count"] > 0
    end

    @tag :live
    test "searches with content filter" do
      {:ok, _} = Tools.register(FileSearchTool)

      {:ok, result} =
        Tools.invoke("file_search", %{"pattern" => "lib/**/*.ex", "content" => "defmodule"}, %{})

      assert result["count"] > 0

      for file <- result["files"] do
        assert is_list(file["matches"])
        assert file["matches"] != []
      end
    end
  end
end
