defmodule Codex.Config.Constrained do
  @moduledoc false
  # Internal wrapper type for configuration values with validation constraints.
  #
  # Used for approval policies and sandbox policies that may be restricted
  # by requirements.toml or managed_config.toml. Aligns with upstream
  # `Constrained<T>` type in codex-rs.

  alias Codex.Config.ConstraintError

  @type constraint(t) :: :any | {:only, [t]} | {:not, [t]}

  @type t(value_type) :: %__MODULE__{
          value: value_type,
          constraint: constraint(value_type)
        }

  @type any_t(value_type) :: %__MODULE__{
          value: value_type,
          constraint: :any
        }

  @type invalid_value_error :: %ConstraintError{
          type: :invalid_value,
          candidate: String.t(),
          allowed: String.t() | nil,
          disallowed: String.t() | nil,
          field_name: nil
        }

  @type t :: t(any())

  defstruct [:value, constraint: :any]

  @doc "Create with no constraints (any value allowed)"
  @spec allow_any(value) :: any_t(value) when value: any()
  def allow_any(value), do: %__MODULE__{value: value, constraint: :any}

  @doc "Create with only specific values allowed"
  @spec allow_only(value, [value]) :: t(value) when value: any()
  def allow_only(value, allowed) when is_list(allowed) do
    %__MODULE__{value: value, constraint: {:only, allowed}}
  end

  @doc "Create with specific values disallowed"
  @spec allow_not(value, [value]) :: t(value) when value: any()
  def allow_not(value, disallowed) when is_list(disallowed) do
    %__MODULE__{value: value, constraint: {:not, disallowed}}
  end

  @doc "Get the current value"
  @spec value(t(value)) :: value when value: any()
  def value(%__MODULE__{value: value}), do: value

  @doc "Check if a value can be set (without mutating)"
  @spec can_set?(t(), any()) :: boolean()
  def can_set?(%__MODULE__{constraint: :any}, _candidate), do: true

  def can_set?(%__MODULE__{constraint: {:only, allowed}}, candidate) do
    candidate in allowed
  end

  def can_set?(%__MODULE__{constraint: {:not, disallowed}}, candidate) do
    candidate not in disallowed
  end

  @doc "Attempt to set a value, returning error if constrained"
  @spec set(t(value), value) :: {:ok, t(value)} | {:error, invalid_value_error()}
        when value: any()
  def set(%__MODULE__{} = constrained, candidate) do
    if can_set?(constrained, candidate) do
      {:ok, %{constrained | value: candidate}}
    else
      {:error, constraint_error(constrained.constraint, candidate)}
    end
  end

  defp constraint_error({:only, allowed}, candidate) do
    %ConstraintError{
      type: :invalid_value,
      candidate: inspect(candidate),
      allowed: inspect(allowed)
    }
  end

  defp constraint_error({:not, disallowed}, candidate) do
    %ConstraintError{
      type: :invalid_value,
      candidate: inspect(candidate),
      disallowed: inspect(disallowed)
    }
  end
end
