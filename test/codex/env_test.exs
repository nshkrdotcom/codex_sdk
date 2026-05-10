defmodule Codex.EnvTest do
  use ExUnit.Case, async: false

  alias Codex.Env

  setup do
    original = Application.get_env(:codex_sdk, :env, %{})

    on_exit(fn ->
      Application.put_env(:codex_sdk, :env, original)
    end)

    :ok
  end

  test "all/1 merges normalized configured env with overrides" do
    Application.put_env(:codex_sdk, :env, %{"CODEX_HOME" => "/tmp/codex", :DROP => nil})

    assert Env.all(CODEX_HOME: "/tmp/override", EXTRA: 123) == %{
             "CODEX_HOME" => "/tmp/override",
             "EXTRA" => "123"
           }
  end

  test "get/2 reads caller supplied env without ambient fallback" do
    Application.put_env(:codex_sdk, :env, %{"CODEX_HOME" => "/tmp/codex"})

    assert Env.get("CODEX_HOME", %{}) == nil
    assert Env.get("CODEX_HOME", CODEX_HOME: "/tmp/explicit") == "/tmp/explicit"
  end
end
