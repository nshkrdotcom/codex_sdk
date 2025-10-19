defmodule Codex.Approvals.StaticPolicy do
  @moduledoc """
  Simple allow/deny approval policy used for tests and defaults.
  """

  @enforce_keys [:mode]
  defstruct [:mode, :reason]

  @type t :: %__MODULE__{mode: :allow | :deny, reason: String.t() | nil}

  @doc """
  Always allow approvals.
  """
  @spec allow(keyword()) :: t()
  def allow(opts \\ []) do
    %__MODULE__{mode: :allow, reason: Keyword.get(opts, :reason)}
  end

  @doc """
  Always deny approvals with an optional reason.
  """
  @spec deny(keyword()) :: t()
  def deny(opts \\ []) do
    %__MODULE__{mode: :deny, reason: Keyword.get(opts, :reason, "denied")}
  end

  @doc false
  @spec review_tool(t(), map(), map()) :: :allow | {:deny, String.t()}
  def review_tool(%__MODULE__{mode: :allow}, _event, _context), do: :allow

  def review_tool(%__MODULE__{mode: :deny, reason: reason}, _event, _context) do
    {:deny, reason}
  end
end
