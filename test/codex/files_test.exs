defmodule Codex.FilesTest do
  use ExUnit.Case, async: true

  alias Codex.Files

  setup do
    Application.put_env(:codex_sdk, :attachment_ttl_ms, 1_000)
    Application.put_env(:codex_sdk, :attachment_cleanup_interval_ms, 50)
    Files.reset!()

    on_exit(fn ->
      Files.reset!()
      Application.delete_env(:codex_sdk, :attachment_ttl_ms)
      Application.delete_env(:codex_sdk, :attachment_cleanup_interval_ms)
    end)

    :ok
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

    test "records inserted_at and ttl metadata" do
      source = tmp_file!("ttl.txt", "ttl data")
      {:ok, attachment} = Files.stage(source, ttl_ms: 5_000)

      assert %DateTime{} = attachment.inserted_at
      assert attachment.ttl_ms == 5_000

      default_source = tmp_file!("ttl_default.txt", "other ttl data")
      {:ok, default_ttl_attachment} = Files.stage(default_source)
      assert default_ttl_attachment.ttl_ms == 1_000

      infinite_source = tmp_file!("ttl_inf.txt", "infinite ttl data")
      {:ok, infinite} = Files.stage(infinite_source, ttl_ms: :infinity)
      assert infinite.ttl_ms == :infinity
    end
  end

  describe "force_cleanup/0" do
    test "removes non-persistent staged files" do
      source = tmp_file!("temp.txt", "123")

      {:ok, attachment} = Files.stage(source, ttl_ms: 0)
      assert File.exists?(attachment.path)

      assert :ok = Files.force_cleanup()

      refute File.exists?(attachment.path)
    end

    test "respects persist flag" do
      source = tmp_file!("persist.txt", "abc")

      {:ok, attachment} = Files.stage(source, persist: true)

      Process.sleep(5)
      assert :ok = Files.force_cleanup()

      assert File.exists?(attachment.path)
    end
  end

  describe "metrics/0" do
    test "returns counts and bytes for staged files" do
      {:ok, a1} = Files.stage(tmp_file!("a1.txt", "123"))
      {:ok, a2} = Files.stage(tmp_file!("a2.txt", "abcdef"), persist: true)

      metrics = Files.metrics()

      assert metrics.total_count == 2
      assert metrics.total_bytes == a1.size + a2.size
      assert metrics.persistent_count == 1
      assert metrics.persistent_bytes == a2.size
    end
  end

  describe "error contracts" do
    test "force_cleanup/0 returns {:error, reason} when registry cannot start" do
      stop_registry()
      table = create_conflicting_manifest_table()

      on_exit(fn -> cleanup_conflicting_manifest_table(table) end)

      assert {:error, _reason} = Files.force_cleanup()
    end

    test "reset!/0 returns {:error, reason} when registry cannot start" do
      stop_registry()
      table = create_conflicting_manifest_table()

      on_exit(fn -> cleanup_conflicting_manifest_table(table) end)

      assert {:error, _reason} = Files.reset!()
    end

    test "metrics/0 returns {:error, reason} when registry cannot start" do
      stop_registry()
      table = create_conflicting_manifest_table()

      on_exit(fn -> cleanup_conflicting_manifest_table(table) end)

      assert {:error, _reason} = Files.metrics()
    end
  end

  describe "telemetry" do
    test "emits staged and cleaned events" do
      handler_id = "files-telemetry-#{System.unique_integer([:positive])}"

      :ok =
        :telemetry.attach_many(
          handler_id,
          [
            [:codex, :attachment, :staged],
            [:codex, :attachment, :cleaned]
          ],
          &__MODULE__.forward_event/4,
          self()
        )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, attachment} = Files.stage(tmp_file!("telemetry.txt", "payload"), ttl_ms: 10)

      assert_receive {:telemetry_event, [:codex, :attachment, :staged], measurements, metadata}
      assert measurements.size_bytes == attachment.size
      assert metadata.checksum == attachment.checksum
      assert metadata.persist? == false
      assert metadata.ttl_ms == 10

      Process.sleep(15)
      Files.force_cleanup()

      assert_receive {:telemetry_event, [:codex, :attachment, :cleaned], clean_measurements,
                      clean_metadata}

      assert clean_measurements.count == 1
      assert clean_measurements.bytes == attachment.size
      assert clean_metadata.checksum == attachment.checksum
    end
  end

  defp tmp_file!(name, contents) do
    dir = Path.join(System.tmp_dir!(), "codex_files_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, name)
    File.write!(path, contents)
    path
  end

  defp stop_registry do
    case Process.whereis(Codex.Files.Registry) do
      pid when is_pid(pid) -> GenServer.stop(pid, :normal)
      _ -> :ok
    end
  end

  defp create_conflicting_manifest_table do
    :ets.new(:codex_files_manifest, [:named_table, :set, :public])
  end

  defp cleanup_conflicting_manifest_table(table) do
    if :ets.info(table) != :undefined do
      try do
        :ets.delete(table)
      rescue
        ArgumentError -> :ok
      catch
        :error, _ -> :ok
      end
    end

    stop_registry()
  end

  def forward_event(event, measurements, metadata, pid) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end
end
