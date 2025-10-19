defmodule Codex.FilesTest do
  use ExUnit.Case, async: true

  alias Codex.Files

  setup do
    Files.reset!()
    on_exit(fn -> Files.reset!() end)
  end

  describe "stage/2" do
    test "copies file into staging directory with checksum metadata" do
      source = tmp_file!("hello.txt", "hello world")

      assert {:ok, attachment} = Files.stage(source)

      assert File.exists?(attachment.path)
      assert attachment.name == "hello.txt"
      assert attachment.size == byte_size("hello world")
      assert byte_size(Base.decode16!(attachment.checksum, case: :lower)) == 32
    end

    test "deduplicates identical files by checksum" do
      source = tmp_file!("dup.txt", "same")

      {:ok, first} = Files.stage(source)
      {:ok, second} = Files.stage(source)

      assert first.id == second.id
      assert first.path == second.path

      staged_files = Files.list_staged()
      assert Enum.count(staged_files) == 1
    end
  end

  describe "cleanup/0" do
    test "removes non-persistent staged files" do
      source = tmp_file!("temp.txt", "123")

      {:ok, attachment} = Files.stage(source)
      assert File.exists?(attachment.path)

      Files.cleanup!()

      refute File.exists?(attachment.path)
    end

    test "respects persist flag" do
      source = tmp_file!("persist.txt", "abc")

      {:ok, attachment} = Files.stage(source, persist: true)

      Files.cleanup!()

      assert File.exists?(attachment.path)
    end
  end

  defp tmp_file!(name, contents) do
    dir = Path.join(System.tmp_dir!(), "codex_files_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, name)
    File.write!(path, contents)
    path
  end
end
