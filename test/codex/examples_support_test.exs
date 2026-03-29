defmodule Codex.ExamplesSupportTest do
  use ExUnit.Case, async: false

  alias CliSubprocessCore.ExecutionSurface
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

  describe "parse_argv/1" do
    test "keeps local defaults when ssh flags are absent" do
      assert {:ok, context} = ExamplesSupport.parse_argv(["--", "hello"])

      assert context.argv == ["hello"]
      assert context.execution_surface == nil
    end

    test "builds ssh execution_surface from shared flags" do
      assert {:ok, context} =
               ExamplesSupport.parse_argv([
                 "--ssh-host",
                 "builder@example.internal",
                 "--ssh-port",
                 "2222",
                 "--ssh-identity-file",
                 "./tmp/id_ed25519"
               ])

      assert %ExecutionSurface{} = context.execution_surface
      assert context.execution_surface.surface_kind == :ssh_exec
      assert context.execution_surface.transport_options[:destination] == "example.internal"
      assert context.execution_surface.transport_options[:ssh_user] == "builder"
      assert context.execution_surface.transport_options[:port] == 2222
      assert context.execution_surface.transport_options[:identity_file] =~ "/tmp/id_ed25519"
    end

    test "rejects orphan ssh flags without --ssh-host" do
      assert {:error, message} = ExamplesSupport.parse_argv(["--ssh-user", "builder"])
      assert message =~ "require --ssh-host"
    end
  end

  describe "codex_options/2" do
    test "injects execution_surface when ssh mode is active" do
      assert {:ok, context} = ExamplesSupport.parse_argv(["--ssh-host", "example.internal"])
      Process.put({ExamplesSupport, :ssh_context}, context)

      assert {:ok, options} = ExamplesSupport.codex_options(%{})

      assert options.execution_surface.surface_kind == :ssh_exec
      assert options.execution_surface.transport_options[:destination] == "example.internal"
      assert is_nil(options.codex_path_override)
    after
      Process.delete({ExamplesSupport, :ssh_context})
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
