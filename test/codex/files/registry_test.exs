defmodule Codex.Files.RegistryTest do
  use ExUnit.Case, async: false

  alias Codex.Files.Attachment
  alias Codex.Files.Registry

  @registry_name :codex_files_registry_test
  @table_name :codex_files_manifest_registry_test

  defmodule BlockingFile do
    @owner_key {__MODULE__, :owner}

    def set_owner(pid) when is_pid(pid), do: :persistent_term.put(@owner_key, pid)
    def clear_owner, do: :persistent_term.erase(@owner_key)

    def mkdir_p!(_path), do: :ok

    def cp!(_source, _destination) do
      owner = :persistent_term.get(@owner_key)
      send(owner, {:blocking_file, :cp_started, self()})

      receive do
        :allow_cp -> :ok
      end

      :ok
    end

    def rm_rf(path) do
      owner = :persistent_term.get(@owner_key)
      send(owner, {:blocking_file, :rm_started, path, self()})

      receive do
        :allow_rm -> :ok
      end

      :ok
    end
  end

  setup do
    BlockingFile.set_owner(self())

    on_exit(fn ->
      BlockingFile.clear_owner()

      case Process.whereis(@registry_name) do
        nil -> :ok
        pid -> GenServer.stop(pid, :normal, 5_000)
      end

      case :ets.whereis(@table_name) do
        :undefined -> :ok
        _ -> :ets.delete(@table_name)
      end
    end)

    :ok
  end

  test "handles metrics calls while stage file copy is in-flight" do
    {:ok, pid} =
      Registry.start_link(
        name: @registry_name,
        manifest_table: @table_name,
        file_module: BlockingFile
      )

    allow_initial_cleanup()

    stage_task =
      Task.async(fn ->
        GenServer.call(pid, {:stage, stage_opts()}, 15_000)
      end)

    assert_receive {:blocking_file, :cp_started, worker_pid}

    assert %{
             total_count: 0,
             total_bytes: 0,
             persistent_count: 0,
             persistent_bytes: 0,
             expirable_count: 0
           } =
             GenServer.call(pid, :metrics)

    send(worker_pid, :allow_cp)

    assert {:ok, %Attachment{checksum: "checksum-1"}} = Task.await(stage_task, 15_000)
  end

  test "handles list calls while force_cleanup is deleting files" do
    {:ok, pid} =
      Registry.start_link(
        name: @registry_name,
        manifest_table: @table_name,
        file_module: BlockingFile
      )

    allow_initial_cleanup()

    stage_task =
      Task.async(fn ->
        GenServer.call(pid, {:stage, stage_opts("checksum-expired", "expired.txt", 1)}, 15_000)
      end)

    assert_receive {:blocking_file, :cp_started, stage_worker}
    send(stage_worker, :allow_cp)

    assert {:ok, %Attachment{path: attachment_path}} = Task.await(stage_task, 15_000)
    Process.sleep(5)

    cleanup_task =
      Task.async(fn ->
        GenServer.call(pid, :force_cleanup, 15_000)
      end)

    assert_receive {:blocking_file, :rm_started, ^attachment_path, cleanup_worker}

    assert [%Attachment{checksum: "checksum-expired"}] = GenServer.call(pid, :list)

    send(cleanup_worker, :allow_rm)

    assert :ok = Task.await(cleanup_task, 15_000)
    assert [] = GenServer.call(pid, :list)
  end

  test "coalesces concurrent stage calls for the same checksum" do
    {:ok, pid} =
      Registry.start_link(
        name: @registry_name,
        manifest_table: @table_name,
        file_module: BlockingFile
      )

    allow_initial_cleanup()

    task_one =
      Task.async(fn ->
        GenServer.call(pid, {:stage, stage_opts("same-checksum", "a.txt", 60_000)}, 15_000)
      end)

    assert_receive {:blocking_file, :cp_started, worker_pid}

    task_two =
      Task.async(fn ->
        GenServer.call(pid, {:stage, stage_opts("same-checksum", "a.txt", 60_000)}, 15_000)
      end)

    Process.sleep(25)
    send(worker_pid, :allow_cp)

    duplicate_copy? =
      receive do
        {:blocking_file, :cp_started, duplicate_worker} ->
          send(duplicate_worker, :allow_cp)
          true
      after
        150 ->
          false
      end

    assert {:ok, %Attachment{checksum: "same-checksum"} = first} = Task.await(task_one, 15_000)
    assert {:ok, %Attachment{checksum: "same-checksum"} = second} = Task.await(task_two, 15_000)

    assert first.path == second.path
    refute duplicate_copy?
  end

  test "ensure_started/0 does not start an unsupervised registry" do
    remove_default_registry_child()

    on_exit(fn ->
      restore_default_registry_child()
    end)

    assert {:error, :not_started} = Registry.ensure_started()
    assert Process.whereis(Codex.Files.Registry) == nil
  end

  defp allow_initial_cleanup do
    assert_receive {:blocking_file, :rm_started, _path, worker_pid}
    send(worker_pid, :allow_rm)
  end

  defp stage_opts(checksum \\ "checksum-1", name \\ "sample.txt", ttl_ms \\ 60_000) do
    %{
      checksum: checksum,
      name: name,
      persist: false,
      ttl_ms: ttl_ms,
      size: 12,
      source_path: "/tmp/source.txt",
      destination_path: "/tmp/codex/#{name}"
    }
  end

  defp remove_default_registry_child do
    if Process.whereis(Codex.Supervisor) && Process.whereis(Codex.Files.Registry) do
      :ok = Supervisor.terminate_child(Codex.Supervisor, Codex.Files.Registry)
      :ok = Supervisor.delete_child(Codex.Supervisor, Codex.Files.Registry)
    end
  end

  defp restore_default_registry_child do
    if Process.whereis(Codex.Supervisor) && is_nil(Process.whereis(Codex.Files.Registry)) do
      {:ok, _pid} = Supervisor.start_child(Codex.Supervisor, {Codex.Files.Registry, []})
    end
  end
end
