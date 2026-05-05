defmodule Codex.TestSupport.GovernedAuthority do
  @moduledoc false

  @ambient_keys ~w(
    CODEX_HOME
    CODEX_API_KEY
    OPENAI_API_KEY
    OPENAI_BASE_URL
    CODEX_MODEL
    OPENAI_DEFAULT_MODEL
    CODEX_MODEL_DEFAULT
    CODEX_PROVIDER_BACKEND
    CODEX_OSS_PROVIDER
    CODEX_OLLAMA_BASE_URL
    CODEX_PATH
  )

  def refs(extra \\ %{}) do
    Map.merge(
      %{
        authority_ref: "authz-codex-test",
        credential_lease_ref: "lease-codex-test",
        native_auth_assertion_ref: "native-codex-test",
        connector_instance_ref: "connector-instance-codex-test",
        provider_account_ref: "provider-account-codex-test",
        connector_binding_ref: "connector-binding-codex-test",
        target_ref: "target-codex-test",
        operation_policy_ref: "operation-policy-codex-test",
        materialization_ref: "materialization-codex-test"
      },
      Map.new(extra)
    )
  end

  def command_refs(extra \\ %{}) do
    refs(Map.merge(%{command_ref: "command-codex-test"}, Map.new(extra)))
  end

  def with_clean_ambient(fun) when is_function(fun, 0) do
    original = Map.new(@ambient_keys, fn key -> {key, System.get_env(key)} end)
    Enum.each(@ambient_keys, &System.delete_env/1)

    try do
      fun.()
    after
      Enum.each(original, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end
  end
end
