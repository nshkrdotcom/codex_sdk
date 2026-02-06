defmodule Codex.Files.Registry do
  @moduledoc """
  GenServer-backed manifest that tracks staged file attachments, deduplicates by checksum,
  and prunes expired entries on a schedule. This powers the public `Codex.Files` helpers.
  """

  use GenServer

  alias Codex.Files.Attachment

  @registry __MODULE__
  @manifest_table :codex_files_manifest

  @type stage_opts :: %{
          required(:checksum) => String.t(),
          required(:name) => String.t(),
          required(:persist) => boolean(),
          required(:ttl_ms) => :infinity | pos_integer(),
          required(:size) => non_neg_integer(),
          required(:source_path) => Path.t(),
          required(:destination_path) => Path.t()
        }

  @type work_item ::
          {:stage, GenServer.from(), stage_opts(), DateTime.t()}
          | {:force_cleanup, GenServer.from(), [{String.t(), Attachment.t()}]}
          | {:cleanup_tick, [{String.t(), Attachment.t()}]}
          | {:reset, GenServer.from(), [Attachment.t()], Path.t()}
          | :cleanup_orphaned_staging

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @registry)
    init_opts = Keyword.delete(opts, :name)
    GenServer.start_link(__MODULE__, init_opts, name: name)
  end

  @doc """
  Ensures the registry is running, starting it under the current process when necessary.
  """
  @spec ensure_started() :: {:ok, pid()} | {:error, term()}
  def ensure_started do
    case Process.whereis(@registry) do
      nil ->
        case start_unlinked() do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, _} = error -> error
        end

      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          {:ok, pid}
        else
          ensure_started()
        end
    end
  catch
    :exit, reason -> {:error, reason}
  end

  @doc """
  Inserts or refreshes a staged attachment using the supplied options, returning the
  canonical `Attachment` struct stored in ETS.
  """
  @spec stage(stage_opts()) :: {:ok, Attachment.t()} | {:error, term()}
  def stage(opts) when is_map(opts) do
    GenServer.call(@registry, {:stage, opts})
  end

  @doc """
  Lists all staged attachments currently tracked in the manifest.
  """
  @spec list() :: [Attachment.t()]
  def list do
    GenServer.call(@registry, :list)
  end

  @doc """
  Aggregates counts, sizes, and TTL information for staged attachments.
  """
  @spec metrics() :: map()
  def metrics do
    GenServer.call(@registry, :metrics)
  end

  @doc """
  Triggers an immediate cleanup pass to remove expired attachments.
  """
  @spec force_cleanup() :: :ok | {:error, term()}
  def force_cleanup do
    GenServer.call(@registry, :force_cleanup)
  end

  @doc """
  Clears the manifest and deletes staged files within the provided staging directory.
  """
  @spec reset(Path.t()) :: :ok | {:error, term()}
  def reset(staging_dir) do
    GenServer.call(@registry, {:reset, staging_dir})
  end

  defp start_unlinked do
    GenServer.start(__MODULE__, [], name: @registry)
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    manifest_table = Keyword.get(opts, :manifest_table, @manifest_table)
    file_module = Keyword.get(opts, :file_module, File)

    table =
      :ets.new(manifest_table, [
        :named_table,
        :set,
        :protected,
        read_concurrency: true,
        write_concurrency: true
      ])

    interval = cleanup_interval()

    state = %{
      table: table,
      table_name: manifest_table,
      file_module: file_module,
      cleanup_interval_ms: interval,
      cleanup_timer: schedule_cleanup(interval),
      work_queue: :queue.new(),
      in_flight: nil
    }

    {:ok, state, {:continue, :cleanup_orphaned_staging}}
  end

  @impl true
  def handle_continue(:cleanup_orphaned_staging, state) do
    state = state |> enqueue_work(:cleanup_orphaned_staging) |> maybe_start_work()
    {:noreply, state}
  end

  @impl true
  def handle_call({:stage, opts}, from, state) do
    now = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    case :ets.lookup(state.table, opts.checksum) do
      [{_checksum, %Attachment{} = existing}] ->
        updated = merge_attachment(existing, opts, now)
        :ets.insert(state.table, {updated.checksum, updated})
        emit_staged(updated, cached?: true)
        {:reply, {:ok, updated}, state}

      [] ->
        state = state |> enqueue_work({:stage, from, opts, now}) |> maybe_start_work()
        {:noreply, state}
    end
  end

  def handle_call(:list, _from, state) do
    {:reply, list_attachments(state.table), state}
  end

  def handle_call(:metrics, _from, state) do
    metrics = :ets.foldl(&accumulate_metrics/2, initial_metrics(), state.table)
    {:reply, metrics, state}
  end

  def handle_call(:force_cleanup, from, state) do
    expired = expired_entries(state.table, DateTime.utc_now())
    state = state |> enqueue_work({:force_cleanup, from, expired}) |> maybe_start_work()
    {:noreply, state}
  end

  def handle_call({:reset, staging_dir}, from, state) do
    attachments = list_attachments(state.table)
    state = state |> enqueue_work({:reset, from, attachments, staging_dir}) |> maybe_start_work()
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup_tick, state) do
    expired = expired_entries(state.table, DateTime.utc_now())
    state = state |> enqueue_work({:cleanup_tick, expired}) |> maybe_start_work()
    {:noreply, state}
  end

  def handle_info(
        {:work_result, pid, result},
        %{in_flight: %{pid: pid, ref: ref, work: work}} = state
      ) do
    Process.demonitor(ref, [:flush])
    state = %{state | in_flight: nil}
    state = handle_completed_work(state, work, result)
    {:noreply, maybe_start_work(state)}
  end

  def handle_info({:work_result, _pid, _result}, state) do
    {:noreply, state}
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{in_flight: %{ref: ref, work: work}} = state
      ) do
    state = %{state | in_flight: nil}
    state = handle_failed_work(state, work, {:worker_down, reason})
    {:noreply, maybe_start_work(state)}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    _ = Process.cancel_timer(state.cleanup_timer)

    if state.in_flight do
      Process.demonitor(state.in_flight.ref, [:flush])

      if Process.alive?(state.in_flight.pid) do
        Process.exit(state.in_flight.pid, :shutdown)
      end

      reply_work_error(state.in_flight.work, :closed)
    end

    state.work_queue
    |> :queue.to_list()
    |> Enum.each(&reply_work_error(&1, :closed))

    :ok
  end

  defp enqueue_work(state, work) do
    %{state | work_queue: :queue.in(work, state.work_queue)}
  end

  defp maybe_start_work(%{in_flight: nil, work_queue: work_queue} = state) do
    case :queue.out(work_queue) do
      {:empty, _} ->
        state

      {{:value, work}, rest} ->
        start_work(%{state | work_queue: rest}, work)
    end
  end

  defp maybe_start_work(state), do: state

  defp start_work(state, work) do
    parent = self()

    runner = fn ->
      result = perform_work(state.file_module, work)
      send(parent, {:work_result, self(), result})
    end

    {:ok, pid} = start_task(runner)
    ref = Process.monitor(pid)
    %{state | in_flight: %{ref: ref, pid: pid, work: work}}
  end

  @spec start_task((-> any())) :: {:ok, pid()}
  defp start_task(fun) do
    case Task.Supervisor.start_child(Codex.TaskSupervisor, fun) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, _} -> Task.start(fun)
    end
  catch
    :exit, _ -> Task.start(fun)
  end

  defp perform_work(file_module, {:stage, _from, opts, _now}) do
    file_module.mkdir_p!(Path.dirname(opts.destination_path))
    file_module.cp!(opts.source_path, opts.destination_path)
    :ok
  end

  defp perform_work(file_module, {:force_cleanup, _from, entries}) do
    Enum.each(entries, fn {_checksum, attachment} ->
      _ = file_module.rm_rf(attachment.path)
    end)

    :ok
  end

  defp perform_work(file_module, {:cleanup_tick, entries}) do
    Enum.each(entries, fn {_checksum, attachment} ->
      _ = file_module.rm_rf(attachment.path)
    end)

    :ok
  end

  defp perform_work(file_module, {:reset, _from, attachments, staging_dir}) do
    Enum.each(attachments, fn attachment ->
      _ = file_module.rm_rf(attachment.path)
    end)

    _ = file_module.rm_rf(staging_dir)
    :ok
  end

  defp perform_work(file_module, :cleanup_orphaned_staging) do
    _ = file_module.rm_rf(Codex.Files.staging_dir())
    :ok
  end

  defp handle_completed_work(state, work, :ok) do
    handle_succeeded_work(state, work)
  end

  defp handle_completed_work(state, work, {:error, reason}) do
    handle_failed_work(state, work, reason)
  end

  defp handle_completed_work(state, work, other) do
    handle_failed_work(state, work, {:unexpected_work_result, other})
  end

  defp handle_succeeded_work(state, {:stage, from, opts, now}) do
    attachment = build_attachment(opts, now)
    :ets.insert(state.table, {attachment.checksum, attachment})
    emit_staged(attachment, cached?: false)
    GenServer.reply(from, {:ok, attachment})
    state
  end

  defp handle_succeeded_work(state, {:force_cleanup, from, entries}) do
    apply_cleanup_entries(state.table, entries)
    GenServer.reply(from, :ok)
    reschedule_cleanup(state)
  end

  defp handle_succeeded_work(state, {:cleanup_tick, entries}) do
    apply_cleanup_entries(state.table, entries)
    reschedule_cleanup(state)
  end

  defp handle_succeeded_work(state, {:reset, from, attachments, _staging_dir}) do
    Enum.each(attachments, fn attachment ->
      :ets.delete(state.table, attachment.checksum)
    end)

    GenServer.reply(from, :ok)
    reschedule_cleanup(state)
  end

  defp handle_succeeded_work(state, :cleanup_orphaned_staging), do: state

  defp handle_failed_work(state, {:stage, from, _opts, _now}, reason) do
    GenServer.reply(from, {:error, reason})
    state
  end

  defp handle_failed_work(state, {:force_cleanup, from, _entries}, reason) do
    GenServer.reply(from, {:error, reason})
    reschedule_cleanup(state)
  end

  defp handle_failed_work(state, {:cleanup_tick, _entries}, _reason) do
    reschedule_cleanup(state)
  end

  defp handle_failed_work(state, {:reset, from, _attachments, _staging_dir}, reason) do
    GenServer.reply(from, {:error, reason})
    reschedule_cleanup(state)
  end

  defp handle_failed_work(state, :cleanup_orphaned_staging, _reason), do: state

  defp reply_work_error({:stage, from, _opts, _now}, reason) do
    GenServer.reply(from, {:error, reason})
  end

  defp reply_work_error({:force_cleanup, from, _entries}, reason) do
    GenServer.reply(from, {:error, reason})
  end

  defp reply_work_error({:reset, from, _attachments, _staging_dir}, reason) do
    GenServer.reply(from, {:error, reason})
  end

  defp reply_work_error({:cleanup_tick, _entries}, _reason), do: :ok
  defp reply_work_error(:cleanup_orphaned_staging, _reason), do: :ok

  defp merge_attachment(%Attachment{} = existing, opts, now) do
    ttl_ms = normalize_ttl(existing.ttl_ms, opts.ttl_ms, opts.persist)
    persist = existing.persist || opts.persist

    %Attachment{
      existing
      | persist: persist,
        ttl_ms: ttl_ms,
        inserted_at: now
    }
  end

  defp build_attachment(opts, now) do
    %Attachment{
      id: opts.checksum,
      name: opts.name,
      path: opts.destination_path,
      checksum: opts.checksum,
      size: opts.size,
      persist: opts.persist,
      inserted_at: now,
      ttl_ms: opts.ttl_ms
    }
  end

  defp emit_staged(%Attachment{} = attachment, metadata) do
    :telemetry.execute(
      [:codex, :attachment, :staged],
      %{size_bytes: attachment.size},
      Map.merge(
        %{
          checksum: attachment.checksum,
          name: attachment.name,
          persist?: attachment.persist,
          ttl_ms: attachment.ttl_ms
        },
        Map.new(metadata)
      )
    )
  end

  defp expired_entries(table, now) do
    table
    |> :ets.tab2list()
    |> Enum.filter(fn {_checksum, attachment} ->
      expirable?(attachment) and expired?(attachment, now)
    end)
  end

  defp apply_cleanup_entries(table, entries) do
    Enum.each(entries, fn {checksum, attachment} ->
      :ets.delete(table, checksum)

      :telemetry.execute(
        [:codex, :attachment, :cleaned],
        %{count: 1, bytes: attachment.size},
        %{
          checksum: attachment.checksum,
          name: attachment.name,
          ttl_ms: attachment.ttl_ms
        }
      )
    end)
  end

  defp list_attachments(table) do
    table
    |> :ets.tab2list()
    |> Enum.map(fn {_checksum, attachment} -> attachment end)
  end

  defp expirable?(%Attachment{persist: true}), do: false
  defp expirable?(%Attachment{ttl_ms: :infinity}), do: false
  defp expirable?(%Attachment{}), do: true

  defp expired?(%Attachment{inserted_at: inserted_at, ttl_ms: ttl_ms}, now)
       when is_integer(ttl_ms) do
    DateTime.diff(now, inserted_at, :millisecond) >= ttl_ms
  end

  defp normalize_ttl(current_ttl, new_ttl, persist?) do
    cond do
      persist? -> :infinity
      current_ttl == :infinity -> :infinity
      new_ttl == :infinity -> :infinity
      is_integer(new_ttl) -> new_ttl
      true -> current_ttl
    end
  end

  defp initial_metrics do
    %{
      total_count: 0,
      total_bytes: 0,
      persistent_count: 0,
      persistent_bytes: 0,
      expirable_count: 0
    }
  end

  defp accumulate_metrics({_checksum, attachment}, acc) do
    acc
    |> Map.update!(:total_count, &(&1 + 1))
    |> Map.update!(:total_bytes, &(&1 + attachment.size))
    |> bump_persist_counter(attachment.persist, attachment.size)
  end

  defp bump_persist_counter(acc, true, size) do
    acc
    |> Map.update!(:persistent_count, &(&1 + 1))
    |> Map.update!(:persistent_bytes, &(&1 + size))
  end

  defp bump_persist_counter(acc, false, _size), do: Map.update!(acc, :expirable_count, &(&1 + 1))

  defp cleanup_interval do
    Application.get_env(:codex_sdk, :attachment_cleanup_interval_ms, 60_000)
  end

  defp schedule_cleanup(interval_ms) do
    Process.send_after(self(), :cleanup_tick, interval_ms)
  end

  defp reschedule_cleanup(state) do
    _ = Process.cancel_timer(state.cleanup_timer)
    %{state | cleanup_timer: schedule_cleanup(state.cleanup_interval_ms)}
  end
end
