defmodule Codex.Session.Memory do
  @moduledoc """
  In-memory session adapter backed by an Agent. Suitable for tests and short-lived runs.
  """

  @behaviour Codex.Session

  @doc """
  Starts a new memory session agent.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    Agent.start_link(fn -> Keyword.get(opts, :history, []) end)
  end

  @impl true
  def load(pid) when is_pid(pid) do
    {:ok, Agent.get(pid, & &1)}
  end

  @impl true
  def save(pid, entry) when is_pid(pid) do
    Agent.update(pid, fn history -> history ++ [entry] end)
    :ok
  end

  @impl true
  def clear(pid) when is_pid(pid) do
    Agent.update(pid, fn _ -> [] end)
    :ok
  end
end
