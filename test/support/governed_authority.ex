defmodule Codex.TestSupport.GovernedAuthority do
  @moduledoc false

  alias Codex.TestSupport.Env

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
    extra = Map.new(extra)
    config_root = Map.get(extra, :config_root, "/tmp/materialized-codex-home")
    base_url = Map.get(extra, :base_url, "https://materialized.example.com/v1")
    issued_at = Map.get(extra, :issued_at, DateTime.utc_now() |> DateTime.add(-60, :second))
    expires_at = Map.get(extra, :expires_at, DateTime.add(issued_at, 3_600, :second))

    env =
      Map.get(extra, :env, %{
        "CODEX_API_KEY" => "materialized-key",
        "OPENAI_API_KEY" => "materialized-key",
        "OPENAI_BASE_URL" => base_url,
        "CODEX_HOME" => config_root
      })

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
        materialization_ref: "materialization-codex-test",
        endpoint_ref: "endpoint-codex-test",
        operation_ref: "operation-codex-test",
        account_namespace: "account:codex:test",
        command: "/bin/true",
        cwd: System.tmp_dir!(),
        env: env,
        config_root: config_root,
        auth_root: config_root,
        base_url: base_url,
        clear_env?: true,
        generation: 1,
        fence: 0,
        issued_at: issued_at,
        expires_at: expires_at
      },
      extra
    )
  end

  def command_refs(extra \\ %{}), do: refs(extra)

  def with_clean_ambient(fun) when is_function(fun, 0) do
    original = Map.new(@ambient_keys, fn key -> {key, System.get_env(key)} end)
    Enum.each(@ambient_keys, &Env.delete/1)

    try do
      fun.()
    after
      Enum.each(original, fn
        {key, nil} -> Env.delete(key)
        {key, value} -> Env.put(key, value)
      end)
    end
  end
end
