defmodule Codex.Config.ConstraintError do
  @moduledoc false
  # Internal module for configuration constraint violations.
  # Used when a constrained configuration value is set to a disallowed value.

  @type t :: %__MODULE__{
          type: :invalid_value | :empty_field,
          candidate: String.t() | nil,
          allowed: String.t() | nil,
          disallowed: String.t() | nil,
          field_name: String.t() | nil
        }

  defexception [:type, :candidate, :allowed, :disallowed, :field_name]

  @impl true
  def message(%{type: :invalid_value, candidate: candidate, allowed: allowed})
      when not is_nil(allowed) do
    "Invalid value #{candidate}; allowed values: #{allowed}"
  end

  def message(%{type: :invalid_value, candidate: candidate, disallowed: disallowed})
      when not is_nil(disallowed) do
    "Invalid value #{candidate}; disallowed values: #{disallowed}"
  end

  def message(%{type: :invalid_value, candidate: candidate}) do
    "Invalid value #{candidate}"
  end

  def message(%{type: :empty_field, field_name: field}) do
    "Field #{field} cannot be empty"
  end
end
