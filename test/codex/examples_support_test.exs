defmodule Codex.ExamplesSupportTest do
  use ExUnit.Case, async: false

  alias Codex.ExamplesSupport

  describe "conversation_default_mode/0" do
    test "uses multi-turn mode outside Ollama" do
      restore = capture_env()

      on_exit(fn ->
        restore_env(restore)
      end)

      System.delete_env("CODEX_PROVIDER_BACKEND")
      System.delete_env("CODEX_OSS_PROVIDER")

      assert ExamplesSupport.conversation_default_mode() == :multi_turn
    end

    test "uses save-resume mode in Ollama" do
      restore = capture_env()

      on_exit(fn ->
        restore_env(restore)
      end)

      System.put_env("CODEX_PROVIDER_BACKEND", "oss")
      System.put_env("CODEX_OSS_PROVIDER", "ollama")

      assert ExamplesSupport.conversation_default_mode() == :save_resume
    end
  end

  defp capture_env do
    %{
      "CODEX_PROVIDER_BACKEND" => System.get_env("CODEX_PROVIDER_BACKEND"),
      "CODEX_OSS_PROVIDER" => System.get_env("CODEX_OSS_PROVIDER")
    }
  end

  defp restore_env(saved) do
    Enum.each(saved, fn
      {key, nil} -> System.delete_env(key)
      {key, value} -> System.put_env(key, value)
    end)
  end
end
