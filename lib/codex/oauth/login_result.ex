defmodule Codex.OAuth.LoginResult do
  @moduledoc """
  Summary returned by `Codex.OAuth.login/1` and `Codex.OAuth.await_login/2`.
  """

  @enforce_keys [:provider, :flow_used, :storage_used, :auth_mode, :persisted?, :warnings]
  defstruct [
    :provider,
    :flow_used,
    :storage_used,
    :auth_mode,
    :account_id,
    :plan_type,
    :expires_at,
    :persisted?,
    :warnings
  ]

  @type t :: %__MODULE__{
          provider: atom(),
          flow_used: atom(),
          storage_used: atom(),
          auth_mode: atom(),
          account_id: String.t() | nil,
          plan_type: String.t() | nil,
          expires_at: DateTime.t() | nil,
          persisted?: boolean(),
          warnings: [String.t()]
        }
end
