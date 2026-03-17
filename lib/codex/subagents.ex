defmodule Codex.Subagents do
  @moduledoc """
  Deterministic host-side helpers for working with subagent threads over app-server.

  This module intentionally does not expose prompt-shaping operations such as
  spawning or delegating work. It only wraps host-callable thread inspection and
  polling behavior.
  """

  alias Codex.AppServer
  alias Codex.Protocol.SessionSource
  alias Codex.Protocol.SubAgentSource

  @type thread_map :: map()
  @type terminal_turn_status :: :completed | :failed | :interrupted

  @doc """
  Lists subagent threads using `thread/list`.

  This defaults `source_kinds` to `[:sub_agent]`. When you need pagination or
  other raw `thread/list` response metadata, use `Codex.AppServer.thread_list/2`
  directly.
  """
  @spec list(pid(), keyword()) :: {:ok, [thread_map()]} | {:error, term()}
  def list(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    opts = Keyword.put_new(opts, :source_kinds, [:sub_agent])

    with {:ok, %{"data" => threads}} <- AppServer.thread_list(conn, opts) do
      {:ok, threads}
    end
  end

  @doc """
  Lists spawned child threads for a known parent thread id.
  """
  @spec children(pid(), String.t(), keyword()) :: {:ok, [thread_map()]} | {:error, term()}
  def children(conn, parent_thread_id, opts \\ [])
      when is_pid(conn) and is_binary(parent_thread_id) and is_list(opts) do
    opts = Keyword.put_new(opts, :source_kinds, [:sub_agent_thread_spawn])

    with {:ok, threads} <- list(conn, opts) do
      {:ok, Enum.filter(threads, &(parent_thread_id(&1) == parent_thread_id))}
    end
  end

  @doc """
  Reads a known subagent thread using `thread/read`.
  """
  @spec read(pid(), String.t(), keyword()) :: {:ok, thread_map()} | {:error, term()}
  def read(conn, thread_id, opts \\ [])
      when is_pid(conn) and is_binary(thread_id) and is_list(opts) do
    with {:ok, %{"thread" => thread}} <- AppServer.thread_read(conn, thread_id, opts) do
      {:ok, thread}
    end
  end

  @doc """
  Parses the typed source metadata for a thread map or raw `source` payload.
  """
  @spec source(thread_map() | SessionSource.t() | map() | String.t() | atom() | nil) ::
          SessionSource.t()
  def source(%SessionSource{} = source), do: source
  def source(%{"source" => source}), do: SessionSource.from_map(source)
  def source(%{source: source}), do: SessionSource.from_map(source)
  def source(source), do: SessionSource.from_map(source)

  @doc """
  Returns the parent thread id for a spawned child thread source, if present.
  """
  @spec parent_thread_id(thread_map() | SessionSource.t() | map() | String.t() | atom() | nil) ::
          String.t() | nil
  def parent_thread_id(value) do
    case source(value) do
      %SessionSource{
        kind: :sub_agent,
        sub_agent: %SubAgentSource{variant: :thread_spawn, parent_thread_id: thread_id}
      } ->
        thread_id

      _ ->
        nil
    end
  end

  @doc """
  Returns `true` when the thread/source carries an explicit parent-child spawn link.
  """
  @spec child_thread?(thread_map() | SessionSource.t() | map() | String.t() | atom() | nil) ::
          boolean()
  def child_thread?(value), do: not is_nil(parent_thread_id(value))

  @doc """
  Polls a known child thread id until its latest turn reaches a terminal status.

  This uses repeated `thread/read(include_turns: true)` calls and returns the
  latest terminal turn status.
  """
  @spec await(pid(), String.t(), keyword()) :: {:ok, terminal_turn_status()} | {:error, term()}
  def await(conn, thread_id, opts \\ [])
      when is_pid(conn) and is_binary(thread_id) and is_list(opts) do
    timeout_ms = Keyword.get(opts, :timeout, 30_000)
    interval_ms = max(Keyword.get(opts, :interval, 250), 0)
    deadline_ms = System.monotonic_time(:millisecond) + timeout_ms

    do_await(conn, thread_id, true, interval_ms, deadline_ms)
  end

  defp do_await(conn, thread_id, include_turns, interval_ms, deadline_ms) do
    case read(conn, thread_id, include_turns: include_turns) do
      {:ok, thread} ->
        maybe_finish_await(thread, conn, thread_id, include_turns, interval_ms, deadline_ms)

      {:error, _} = error ->
        error
    end
  end

  defp maybe_finish_await(thread, conn, thread_id, include_turns, interval_ms, deadline_ms) do
    case latest_turn_status(thread) do
      {:ok, status} when status in [:completed, :failed, :interrupted] -> {:ok, status}
      _ -> continue_await(conn, thread_id, include_turns, interval_ms, deadline_ms)
    end
  end

  defp continue_await(conn, thread_id, include_turns, interval_ms, deadline_ms) do
    if System.monotonic_time(:millisecond) >= deadline_ms do
      {:error, :timeout}
    else
      Process.sleep(interval_ms)
      do_await(conn, thread_id, include_turns, interval_ms, deadline_ms)
    end
  end

  defp latest_turn_status(%{"turns" => turns}) when is_list(turns), do: latest_turn_status(turns)
  defp latest_turn_status(%{turns: turns}) when is_list(turns), do: latest_turn_status(turns)

  defp latest_turn_status([]), do: :unknown

  defp latest_turn_status(turns) when is_list(turns) do
    turns
    |> List.last()
    |> case do
      %{"status" => status} -> {:ok, normalize_turn_status(status)}
      %{status: status} -> {:ok, normalize_turn_status(status)}
      _ -> :unknown
    end
  end

  defp latest_turn_status(_), do: :unknown

  defp normalize_turn_status("completed"), do: :completed
  defp normalize_turn_status("failed"), do: :failed
  defp normalize_turn_status("interrupted"), do: :interrupted
  defp normalize_turn_status("inProgress"), do: :in_progress
  defp normalize_turn_status("in_progress"), do: :in_progress
  defp normalize_turn_status(status) when is_atom(status), do: status
  defp normalize_turn_status(_), do: :unknown
end
