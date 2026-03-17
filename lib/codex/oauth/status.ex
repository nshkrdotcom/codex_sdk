defmodule Codex.OAuth.Status do
  @moduledoc """
  Current OAuth auth state returned by `Codex.OAuth.status/1` and `refresh/1`.
  """

  @enforce_keys [:authenticated?, :warnings]
  defstruct [
    :authenticated?,
    :provider,
    :storage_used,
    :auth_mode,
    :account_id,
    :plan_type,
    :expires_at,
    :persisted?,
    :warnings
  ]

  @type t :: %__MODULE__{
          authenticated?: boolean(),
          provider: atom() | nil,
          storage_used: atom() | nil,
          auth_mode: atom() | nil,
          account_id: String.t() | nil,
          plan_type: String.t() | nil,
          expires_at: DateTime.t() | nil,
          persisted?: boolean() | nil,
          warnings: [String.t()]
        }
end
