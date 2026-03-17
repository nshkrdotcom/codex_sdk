defmodule Codex.OAuth.Session do
  @moduledoc """
  Internal OAuth session structs shared across flows and token stores.
  """

  defmodule PendingLogin do
    @moduledoc """
    Pending browser-based OAuth login state returned by `Codex.OAuth.begin_login/1`.
    """

    @enforce_keys [
      :provider,
      :flow,
      :storage,
      :context,
      :authorize_url,
      :state,
      :pkce,
      :redirect_uri,
      :loopback_server
    ]
    defstruct [
      :provider,
      :flow,
      :storage,
      :context,
      :authorize_url,
      :state,
      :pkce,
      :redirect_uri,
      :loopback_server,
      :warnings
    ]

    @type t :: %__MODULE__{
            provider: atom(),
            flow: atom(),
            storage: :file | :memory | :auto,
            context: struct(),
            authorize_url: String.t(),
            state: String.t(),
            pkce: struct(),
            redirect_uri: String.t(),
            loopback_server: struct() | nil,
            warnings: [String.t()] | nil
          }
  end

  defmodule PendingDeviceLogin do
    @moduledoc """
    Pending device-code OAuth login state returned by `Codex.OAuth.begin_login/1`.
    """

    @enforce_keys [
      :provider,
      :flow,
      :storage,
      :context,
      :verification_url,
      :user_code,
      :device_code,
      :interval_ms
    ]
    defstruct [
      :provider,
      :flow,
      :storage,
      :context,
      :verification_url,
      :user_code,
      :device_code,
      :interval_ms,
      :expires_at,
      :warnings
    ]

    @type t :: %__MODULE__{
            provider: atom(),
            flow: atom(),
            storage: :file | :memory | :auto,
            context: struct(),
            verification_url: String.t(),
            user_code: String.t(),
            device_code: String.t(),
            interval_ms: pos_integer(),
            expires_at: DateTime.t() | nil,
            warnings: [String.t()] | nil
          }
  end

  @enforce_keys [:provider, :flow, :storage, :context, :auth_record]
  defstruct [
    :provider,
    :flow,
    :storage,
    :context,
    :auth_record,
    :persisted?,
    :token_store
  ]

  @type t :: %__MODULE__{
          provider: atom(),
          flow: atom(),
          storage: :file | :memory | :auto,
          context: struct(),
          auth_record: struct(),
          persisted?: boolean(),
          token_store: pid() | nil
        }
end
