defmodule Codex.Files.Registry do
  @moduledoc false

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

  @spec ensure_started() :: {:ok, pid()} | {:error, term()}
  def ensure_started do
    case Process.whereis(@registry) do
      nil ->
        case GenServer.start(__MODULE__, %{}, name: @registry) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, _} = error -> error
        end

      pid ->
        {:ok, pid}
    end
  end

  @spec stage(stage_opts()) :: {:ok, Attachment.t()} | {:error, term()}
  def stage(opts) when is_map(opts) do
    GenServer.call(@registry, {:stage, opts})
  end

  @spec list() :: [Attachment.t()]
  def list do
    GenServer.call(@registry, :list)
  end

  @spec metrics() :: map()
  def metrics do
    GenServer.call(@registry, :metrics)
  end

  @spec force_cleanup() :: :ok
  def force_cleanup do
    GenServer.call(@registry, :force_cleanup)
  end

  @spec reset(Path.t()) :: :ok
  def reset(staging_dir) do
    GenServer.call(@registry, {:reset, staging_dir})
  end

  # GenServer callbacks

  @impl true
  def init(_) do
    table =
      :ets.new(@manifest_table, [
        :named_table,
        :set,
        :public,
        read_concurrency: true,
        write_concurrency: true
      ])

    interval = cleanup_interval()

    state = %{
      table: table,
      cleanup_interval_ms: interval,
      cleanup_timer: schedule_cleanup(interval)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:stage, opts}, _from, state) do
    now = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    reply =
      case :ets.lookup(@manifest_table, opts.checksum) do
        [{_checksum, %Attachment{} = existing}] ->
          updated = merge_attachment(existing, opts, now)
          :ets.insert(@manifest_table, {updated.checksum, updated})
          emit_staged(updated, cached?: true)
          {:ok, updated}

        [] ->
          attachment = create_attachment(opts, now)

          emit_staged(attachment, cached?: false)
          {:ok, attachment}
      end

    {:reply, reply, state}
  end

  def handle_call(:list, _from, state) do
    attachments =
      @manifest_table
      |> :ets.tab2list()
      |> Enum.map(fn {_checksum, attachment} -> attachment end)

    {:reply, attachments, state}
  end

  def handle_call(:metrics, _from, state) do
    metrics =
      :ets.foldl(&accumulate_metrics/2, initial_metrics(), @manifest_table)

    {:reply, metrics, state}
  end

  def handle_call(:force_cleanup, _from, state) do
    cleanup_expired(DateTime.utc_now())
    {:reply, :ok, reschedule_cleanup(state)}
  end

  def handle_call({:reset, staging_dir}, _from, state) do
    attachments =
      @manifest_table
      |> :ets.tab2list()
      |> Enum.map(fn {_checksum, attachment} -> attachment end)

    Enum.each(attachments, fn attachment ->
      File.rm_rf(attachment.path)
      :ets.delete(@manifest_table, attachment.checksum)
    end)

    File.rm_rf(staging_dir)

    {:reply, :ok, reschedule_cleanup(state)}
  end

  @impl true
  def handle_info(:cleanup_tick, state) do
    cleanup_expired(DateTime.utc_now())
    {:noreply, reschedule_cleanup(state)}
  end

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

  defp create_attachment(opts, now) do
    File.mkdir_p!(Path.dirname(opts.destination_path))
    File.cp!(opts.source_path, opts.destination_path)

    attachment = %Attachment{
      id: opts.checksum,
      name: opts.name,
      path: opts.destination_path,
      checksum: opts.checksum,
      size: opts.size,
      persist: opts.persist,
      inserted_at: now,
      ttl_ms: opts.ttl_ms
    }

    :ets.insert(@manifest_table, {attachment.checksum, attachment})
    attachment
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

  defp cleanup_expired(now) do
    @manifest_table
    |> :ets.tab2list()
    |> Enum.each(fn {checksum, attachment} ->
      if expirable?(attachment) and expired?(attachment, now) do
        File.rm_rf(attachment.path)
        :ets.delete(@manifest_table, checksum)

        :telemetry.execute(
          [:codex, :attachment, :cleaned],
          %{count: 1, bytes: attachment.size},
          %{
            checksum: attachment.checksum,
            name: attachment.name,
            ttl_ms: attachment.ttl_ms
          }
        )
      end
    end)
  end

  defp expirable?(%Attachment{persist: true}), do: false
  defp expirable?(%Attachment{ttl_ms: :infinity}), do: false
  defp expirable?(%Attachment{}), do: true

  defp expired?(%Attachment{ttl_ms: ttl_ms, inserted_at: inserted_at}, now) do
    cutoff = DateTime.add(inserted_at, ttl_ms, :millisecond)
    DateTime.compare(now, cutoff) != :lt
  end

  defp normalize_ttl(:infinity, _new_ttl, _persist), do: :infinity

  defp normalize_ttl(_current_ttl, :infinity, _persist), do: :infinity

  defp normalize_ttl(_current_ttl, _new_ttl, true), do: :infinity

  defp normalize_ttl(current_ttl, new_ttl, _persist)
       when is_integer(current_ttl) and is_integer(new_ttl) do
    max(current_ttl, new_ttl)
  end

  defp schedule_cleanup(interval) when is_integer(interval) and interval > 0 do
    Process.send_after(self(), :cleanup_tick, interval)
  end

  defp schedule_cleanup(_), do: nil

  defp reschedule_cleanup(state) do
    if state.cleanup_timer do
      Process.cancel_timer(state.cleanup_timer)
    end

    interval = cleanup_interval()

    %{state | cleanup_interval_ms: interval, cleanup_timer: schedule_cleanup(interval)}
  end

  defp cleanup_interval do
    Application.get_env(:codex_sdk, :attachment_cleanup_interval_ms, 60_000)
  end

  defp accumulate_metrics({_checksum, attachment}, acc) do
    acc
    |> Map.update!(:total_count, &(&1 + 1))
    |> Map.update!(:total_bytes, &(&1 + attachment.size))
    |> maybe_accumulate_persistent(attachment)
    |> maybe_accumulate_expirable(attachment)
  end

  defp maybe_accumulate_persistent(acc, %Attachment{persist: true, size: size}) do
    acc
    |> Map.update!(:persistent_count, &(&1 + 1))
    |> Map.update!(:persistent_bytes, &(&1 + size))
  end

  defp maybe_accumulate_persistent(acc, _), do: acc

  defp maybe_accumulate_expirable(acc, %Attachment{persist: false, size: size}) do
    acc
    |> Map.update!(:expirable_count, &(&1 + 1))
    |> Map.update!(:expirable_bytes, &(&1 + size))
  end

  defp maybe_accumulate_expirable(acc, _), do: acc

  defp initial_metrics do
    %{
      total_count: 0,
      total_bytes: 0,
      persistent_count: 0,
      persistent_bytes: 0,
      expirable_count: 0,
      expirable_bytes: 0
    }
  end
end
