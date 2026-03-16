defmodule Codex.Runtime.EnvTest do
  use ExUnit.Case, async: false

  alias Codex.Runtime.Env

  setup do
    env_keys = ~w(CODEX_CA_CERTIFICATE SSL_CERT_FILE)

    original_env =
      env_keys
      |> Enum.map(&{&1, System.get_env(&1)})
      |> Map.new()

    Enum.each(env_keys, &System.delete_env/1)

    on_exit(fn ->
      Enum.each(env_keys, fn key ->
        case Map.fetch!(original_env, key) do
          nil -> System.delete_env(key)
          value -> System.put_env(key, value)
        end
      end)
    end)

    :ok
  end

  test "base_overrides propagates the resolved custom CA bundle" do
    System.put_env("SSL_CERT_FILE", "/tmp/ssl.pem")

    overrides = Env.base_overrides("sk-test", "https://gateway.example.com/v1")

    assert overrides["CODEX_API_KEY"] == "sk-test"
    assert overrides["OPENAI_API_KEY"] == "sk-test"
    assert overrides["OPENAI_BASE_URL"] == "https://gateway.example.com/v1"
    assert overrides["CODEX_CA_CERTIFICATE"] == "/tmp/ssl.pem"
    assert overrides["SSL_CERT_FILE"] == "/tmp/ssl.pem"
  end

  test "normalize_overrides accepts maps and keywords and stringifies values" do
    assert {:ok, %{"CODEX_HOME" => "/tmp/codex-home", "EXTRA_FLAG" => "123"}} =
             Env.normalize_overrides(%{
               CODEX_HOME: "/tmp/codex-home",
               EXTRA_FLAG: 123,
               OMIT_ME: nil
             })

    assert {:ok, %{"HOME" => "/tmp/home", "USERPROFILE" => "/tmp/home"}} =
             Env.normalize_overrides(HOME: "/tmp/home", USERPROFILE: "/tmp/home", EMPTY: nil)
  end

  test "normalize_overrides rejects non-keyword lists" do
    assert {:error, {:invalid_env, ["/tmp/not-a-keyword"]}} =
             Env.normalize_overrides(["/tmp/not-a-keyword"])
  end
end
