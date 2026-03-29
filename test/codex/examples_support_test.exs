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
      assert context.example_cwd == nil
    end

    test "builds ssh execution_surface from shared flags" do
      assert {:ok, context} =
               ExamplesSupport.parse_argv([
                 "--cwd",
                 "/srv/codex",
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
      assert context.example_cwd == "/srv/codex"
    end

    test "rejects orphan ssh flags without --ssh-host" do
      assert {:error, message} = ExamplesSupport.parse_argv(["--ssh-user", "builder"])
      assert message =~ "require --ssh-host"
    end

    test "rejects blank cwd values" do
      assert {:error, message} = ExamplesSupport.parse_argv(["--cwd", "   "])
      assert message =~ "--cwd"
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

  describe "thread_opts/1" do
    test "injects skip_git_repo_check in ssh mode" do
      assert {:ok, context} = ExamplesSupport.parse_argv(["--ssh-host", "example.internal"])
      Process.put({ExamplesSupport, :ssh_context}, context)

      assert {:ok, thread_opts} = ExamplesSupport.thread_opts(%{})
      assert thread_opts.skip_git_repo_check == true
    after
      Process.delete({ExamplesSupport, :ssh_context})
    end

    test "forces skip_git_repo_check in ssh mode for example safety" do
      assert {:ok, context} = ExamplesSupport.parse_argv(["--ssh-host", "example.internal"])
      Process.put({ExamplesSupport, :ssh_context}, context)

      assert {:ok, thread_opts} = ExamplesSupport.thread_opts(%{skip_git_repo_check: false})
      assert thread_opts.skip_git_repo_check == true
    after
      Process.delete({ExamplesSupport, :ssh_context})
    end

    test "injects shared cwd when explicitly configured" do
      assert {:ok, context} = ExamplesSupport.parse_argv(["--cwd", "/srv/codex"])
      Process.put({ExamplesSupport, :ssh_context}, context)

      assert {:ok, thread_opts} = ExamplesSupport.thread_opts(%{})
      assert thread_opts.working_directory == "/srv/codex"
      assert ExamplesSupport.example_working_directory() == "/srv/codex"
    after
      Process.delete({ExamplesSupport, :ssh_context})
    end

    test "injects ssh defaults for prebuilt Thread.Options structs" do
      assert {:ok, context} =
               ExamplesSupport.parse_argv([
                 "--ssh-host",
                 "example.internal",
                 "--cwd",
                 "/srv/codex"
               ])

      Process.put({ExamplesSupport, :ssh_context}, context)

      assert {:ok, thread_opts} = ExamplesSupport.thread_opts(%Codex.Thread.Options{})
      assert thread_opts.skip_git_repo_check == true
      assert thread_opts.working_directory == "/srv/codex"
    after
      Process.delete({ExamplesSupport, :ssh_context})
    end
  end

  describe "ensure_remote_working_directory/1" do
    test "skips ssh examples that need a remote cwd when none is configured" do
      assert {:ok, context} = ExamplesSupport.parse_argv(["--ssh-host", "example.internal"])
      Process.put({ExamplesSupport, :ssh_context}, context)

      assert {:skip, reason} = ExamplesSupport.ensure_remote_working_directory("need cwd")
      assert reason == "need cwd"
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
