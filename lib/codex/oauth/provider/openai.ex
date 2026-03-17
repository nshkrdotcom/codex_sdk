defmodule Codex.OAuth.Provider.OpenAI do
  @moduledoc false

  @default_client_id "app_EMoamEEZ73f0CkXaXp7hrann"
  @default_scope "openid profile email offline_access api.connectors.read api.connectors.invoke"
  @default_originator "codex_sdk_elixir"

  @enforce_keys [
    :issuer,
    :client_id,
    :authorize_url,
    :token_url,
    :device_authorization_url,
    :device_token_url,
    :device_verification_url,
    :scope,
    :originator
  ]
  defstruct [
    :issuer,
    :client_id,
    :authorize_url,
    :token_url,
    :device_authorization_url,
    :device_token_url,
    :device_verification_url,
    :scope,
    :originator
  ]

  @type t :: %__MODULE__{
          issuer: String.t(),
          client_id: String.t(),
          authorize_url: String.t(),
          token_url: String.t(),
          device_authorization_url: String.t(),
          device_token_url: String.t(),
          device_verification_url: String.t(),
          scope: String.t(),
          originator: String.t()
        }

  @spec default_issuer() :: String.t()
  def default_issuer, do: "https://auth.openai.com"

  @spec build(keyword()) :: t()
  def build(opts \\ []) when is_list(opts) do
    issuer =
      opts
      |> Keyword.get(:issuer, default_issuer())
      |> String.trim_trailing("/")

    client_id = Keyword.get(opts, :client_id, @default_client_id)

    %__MODULE__{
      issuer: issuer,
      client_id: client_id,
      authorize_url: Keyword.get(opts, :authorize_url, issuer <> "/oauth/authorize"),
      token_url: Keyword.get(opts, :token_url, issuer <> "/oauth/token"),
      device_authorization_url:
        Keyword.get(
          opts,
          :device_authorization_url,
          issuer <> "/api/accounts/deviceauth/usercode"
        ),
      device_token_url:
        Keyword.get(opts, :device_token_url, issuer <> "/api/accounts/deviceauth/token"),
      device_verification_url:
        Keyword.get(opts, :device_verification_url, issuer <> "/codex/device"),
      scope: Keyword.get(opts, :scope, @default_scope),
      originator: Keyword.get(opts, :originator, @default_originator)
    }
  end
end
