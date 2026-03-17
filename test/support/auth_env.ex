defmodule Codex.TestSupport.AuthEnv do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      import Codex.TestSupport.AuthEnv
    end
  end

  setup do
    tmp_root =
      Path.join(System.tmp_dir!(), "codex_auth_#{System.unique_integer([:positive])}")

    codex_home = Path.join(tmp_root, "home")
    system_path = Path.join(tmp_root, "system_config.toml")

    File.mkdir_p!(codex_home)

    original_env = %{
      "CODEX_HOME" => System.get_env("CODEX_HOME"),
      "CODEX_API_KEY" => System.get_env("CODEX_API_KEY"),
      "OPENAI_API_KEY" => System.get_env("OPENAI_API_KEY")
    }

    original_system_path = Application.get_env(:codex_sdk, :system_config_path)

    System.put_env("CODEX_HOME", codex_home)
    System.delete_env("CODEX_API_KEY")
    System.delete_env("OPENAI_API_KEY")
    Application.put_env(:codex_sdk, :system_config_path, system_path)

    :persistent_term.erase({Codex.Auth, :keyring_warning_emitted})

    on_exit(fn ->
      restore_env(original_env)

      case original_system_path do
        nil -> Application.delete_env(:codex_sdk, :system_config_path)
        value -> Application.put_env(:codex_sdk, :system_config_path, value)
      end

      File.rm_rf(tmp_root)
    end)

    {:ok, tmp_root: tmp_root, codex_home: codex_home, system_path: system_path}
  end

  def restore_env(env) when is_map(env) do
    Enum.each(env, fn {key, value} -> restore_env(key, value) end)
  end

  def restore_env(key, nil), do: System.delete_env(key)
  def restore_env(key, value), do: System.put_env(key, value)
end
