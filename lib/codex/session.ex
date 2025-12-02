defmodule Codex.Session do
  @moduledoc """
  Behaviour for persisting conversation state across runs.
  """

  @callback load(state :: term()) :: {:ok, term()} | {:error, term()}
  @callback save(state :: term(), entry :: term()) :: :ok | {:error, term()}
  @callback clear(state :: term()) :: :ok | {:error, term()}

  @type t :: {module(), term()}

  @doc """
  Loads session history.
  """
  @spec load(t()) :: {:ok, term()} | {:error, term()}
  def load({mod, state}) when is_atom(mod), do: mod.load(state)

  @doc """
  Persists a session entry.
  """
  @spec save(t(), term()) :: :ok | {:error, term()}
  def save({mod, state}, entry) when is_atom(mod), do: mod.save(state, entry)

  @doc """
  Clears stored history.
  """
  @spec clear(t()) :: :ok | {:error, term()}
  def clear({mod, state}) when is_atom(mod), do: mod.clear(state)

  @doc """
  Validates a session reference.
  """
  @spec valid?(term()) :: boolean()
  def valid?({mod, _state}) when is_atom(mod), do: true
  def valid?(_), do: false
end
