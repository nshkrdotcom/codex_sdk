defmodule Codex.Runtime.Erlexec do
  @moduledoc false

  @spec ensure_started() :: :ok | {:error, term()}
  def ensure_started do
    case Application.ensure_all_started(:erlexec) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
      {:error, {:erlexec, {:already_started, _}}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
