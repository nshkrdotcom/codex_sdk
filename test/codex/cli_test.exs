defmodule Codex.CLITest do
  use ExUnit.Case, async: true

  alias CliSubprocessCore.TestSupport.FakeSSH
  alias Codex.{CLI, Options}

  test "run/2 forwards stdin and environment overrides" do
    args_path = tmp_path("argv")
    stdin_path = tmp_path("stdin")

    script_path =
      probe_script(args_path,
        stdin_path: stdin_path,
        stdout: "ok\n"
      )

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

    assert {:ok, result} =
             CLI.run(["login", "--with-api-key"],
               codex_opts: codex_opts,
               stdin: "sk-test\n",
               env: %{"CLI_MODE" => "api"}
             )

    assert result.success
    assert result.exit_code == 0
    assert result.stdout == "ok\n"
    assert argv(args_path) == ["login", "--with-api-key"]
    assert File.read!(stdin_path) == "sk-test\n"
  end

  test "run/2 preserves clear_env? on the shared command lane" do
    args_path = tmp_path("argv_clear_env")
    env_key = "CODEX_CLI_PHASE2A_ENV"
    previous = System.get_env(env_key)
    System.put_env(env_key, "present")

    on_exit(fn ->
      case previous do
        nil -> System.delete_env(env_key)
        value -> System.put_env(env_key, value)
      end
    end)

    script_path = env_probe_script(args_path, env_key)
    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

    assert {:ok, %{stdout: "missing", success: true}} =
             CLI.run(["features", "list"],
               codex_opts: codex_opts,
               clear_env?: true
             )

    assert argv(args_path) == ["features", "list"]
  end

  test "simple wrappers build expected argv" do
    cases = [
      {"completion", fn opts -> CLI.completion("zsh", codex_opts: opts) end,
       ["completion", "zsh"]},
      {"apply", fn opts -> CLI.apply("task_123", codex_opts: opts) end, ["apply", "task_123"]},
      {"debug",
       fn opts ->
         CLI.debug_app_server_send_message_v2("inspect protocol", codex_opts: opts)
       end, ["debug", "app-server", "send-message-v2", "inspect protocol"]},
      {"features list", fn opts -> CLI.features_list(codex_opts: opts) end, ["features", "list"]},
      {"features enable",
       fn opts ->
         CLI.features_enable("unified_exec", codex_opts: opts)
       end, ["features", "enable", "unified_exec"]},
      {"features disable",
       fn opts ->
         CLI.features_disable("shell_snapshot", codex_opts: opts)
       end, ["features", "disable", "shell_snapshot"]},
      {"login status", fn opts -> CLI.login_status(codex_opts: opts) end, ["login", "status"]},
      {"logout", fn opts -> CLI.logout(codex_opts: opts) end, ["logout"]},
      {"cloud list",
       fn opts ->
         CLI.cloud_list(codex_opts: opts, env_id: "env_123", json: true, limit: 5)
       end, ["cloud", "list", "--env", "env_123", "--json", "--limit", "5"]},
      {"cloud exec",
       fn opts ->
         CLI.cloud_exec("Summarize open bugs",
           codex_opts: opts,
           env_id: "env_123",
           attempts: 3,
           model: "gpt-5.4",
           config: %{"features" => %{"skills" => true}}
         )
       end,
       [
         "cloud",
         "exec",
         "--model",
         "gpt-5.4",
         "--config",
         "features.skills=true",
         "--env",
         "env_123",
         "--attempts",
         "3",
         "Summarize open bugs"
       ]},
      {"execpolicy",
       fn opts ->
         CLI.execpolicy_check(["git", "status"],
           codex_opts: opts,
           rules: ["/tmp/a.toml", "/tmp/b.toml"],
           pretty: true
         )
       end,
       [
         "execpolicy",
         "check",
         "--pretty",
         "--rules",
         "/tmp/a.toml",
         "--rules",
         "/tmp/b.toml",
         "--",
         "git",
         "status"
       ]},
      {"sandbox",
       fn opts ->
         CLI.sandbox(["echo", "hi"],
           codex_opts: opts,
           full_auto: true,
           config: ["sandbox_workspace_write.network_access=true"]
         )
       end,
       [
         "sandbox",
         "--full-auto",
         "--config",
         "sandbox_workspace_write.network_access=true",
         "--",
         "echo",
         "hi"
       ]},
      {"app",
       fn opts ->
         CLI.app("/tmp/workspace",
           codex_opts: opts,
           download_url: "https://example.invalid/codex.dmg"
         )
       end, ["app", "--download-url", "https://example.invalid/codex.dmg", "/tmp/workspace"]}
    ]

    Enum.each(cases, fn {label, fun, expected_argv} ->
      args_path = tmp_path("argv_#{label}")
      script_path = probe_script(args_path, stdout: "ok\n")
      {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

      assert {:ok, %{success: true, exit_code: 0}} = fun.(codex_opts),
             "wrapper failed for #{label}"

      assert argv(args_path) == expected_argv, "unexpected argv for #{label}"
    end)
  end

  test "login wrapper can pipe an API key over stdin" do
    args_path = tmp_path("argv_api_key")
    stdin_path = tmp_path("stdin_api_key")

    script_path =
      probe_script(args_path,
        stdin_path: stdin_path,
        stdout: "logged-in\n"
      )

    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

    assert {:ok, %{stdout: "logged-in\n", success: true}} =
             CLI.login({:api_key, "sk-123"},
               codex_opts: codex_opts
             )

    assert argv(args_path) == ["login", "--with-api-key"]
    assert File.read!(stdin_path) == "sk-123\n"
  end

  test "mcp wrappers build stdio and http transport argv" do
    args_path = tmp_path("argv_mcp_stdio")
    script_path = probe_script(args_path, stdout: "ok\n")
    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

    assert {:ok, %{success: true}} =
             CLI.mcp_add("docs", {:command, ["npx", "-y", "mcp-server"]},
               codex_opts: codex_opts,
               env: ["FOO=bar", "BAZ=qux"]
             )

    assert argv(args_path) == [
             "mcp",
             "add",
             "docs",
             "--env",
             "FOO=bar",
             "--env",
             "BAZ=qux",
             "--",
             "npx",
             "-y",
             "mcp-server"
           ]

    args_path = tmp_path("argv_mcp_http")
    script_path = probe_script(args_path, stdout: "ok\n")
    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

    assert {:ok, %{success: true}} =
             CLI.mcp_add("docs", {:url, "https://example.invalid/mcp"},
               codex_opts: codex_opts,
               bearer_token_env_var: "MCP_TOKEN"
             )

    assert argv(args_path) == [
             "mcp",
             "add",
             "docs",
             "--url",
             "https://example.invalid/mcp",
             "--bearer-token-env-var",
             "MCP_TOKEN"
           ]
  end

  test "run/2 preserves execution_surface over fake SSH" do
    fake_ssh = FakeSSH.new!()
    on_exit(fn -> FakeSSH.cleanup(fake_ssh) end)

    args_path = tmp_path("argv_fake_ssh")
    script_path = probe_script(args_path, stdout: "ok\n")
    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

    assert {:ok, %{stdout: "ok\n", success: true}} =
             CLI.run(["features", "list"],
               codex_opts: codex_opts,
               execution_surface: [
                 surface_kind: :ssh_exec,
                 transport_options:
                   FakeSSH.transport_options(fake_ssh,
                     destination: "cli-run.test.example",
                     port: 2222
                   )
               ]
             )

    assert argv(args_path) == ["features", "list"]
    assert FakeSSH.wait_until_written(fake_ssh, 1_000) == :ok
    assert FakeSSH.read_manifest!(fake_ssh) =~ "destination=cli-run.test.example"
  end

  test "run/2 resolves codex against the effective SSH execution_surface instead of local CODEX_PATH" do
    fake_ssh = FakeSSH.new!()
    remote_dir = tmp_path("remote_codex_dir")
    remote_args_path = tmp_path("argv_remote_effective_surface")
    local_args_path = tmp_path("argv_local_effective_surface")
    previous = System.get_env("CODEX_PATH")

    File.mkdir_p!(remote_dir)

    remote_script_path =
      Path.join(remote_dir, "codex")
      |> tap(fn path ->
        body = """
        #!/bin/sh
        printf '%s\\n' "$@" > #{inspect(remote_args_path)}
        printf 'remote-surface\\n'
        """

        File.write!(path, body)
        File.chmod!(path, 0o755)
      end)

    local_script_path = probe_script(local_args_path, stdout: "local-path\n")

    System.put_env("CODEX_PATH", local_script_path)

    on_exit(fn ->
      case previous do
        nil -> System.delete_env("CODEX_PATH")
        value -> System.put_env("CODEX_PATH", value)
      end

      File.rm_rf(remote_dir)
      FakeSSH.cleanup(fake_ssh)
    end)

    assert {:ok, %{stdout: "remote-surface\n", success: true}} =
             CLI.run(["features", "list"],
               execution_surface: [
                 surface_kind: :ssh_exec,
                 transport_options:
                   FakeSSH.transport_options(fake_ssh,
                     destination: "cli-run-effective-surface.example"
                   )
               ],
               env: %{"PATH" => remote_dir}
             )

    assert remote_args_path |> File.read!() |> String.split("\n", trim: true) == [
             "features",
             "list"
           ]

    refute File.exists?(local_args_path)
    assert remote_script_path == Path.join(remote_dir, "codex")
  end

  test "additional mcp wrappers build expected argv" do
    cases = [
      {"get", fn opts -> CLI.mcp_get("docs", codex_opts: opts, json: true) end,
       ["mcp", "get", "docs", "--json"]},
      {"list", fn opts -> CLI.mcp_list(codex_opts: opts, json: true) end,
       ["mcp", "list", "--json"]},
      {"login",
       fn opts ->
         CLI.mcp_login("docs", codex_opts: opts, scopes: ["read", "write"])
       end, ["mcp", "login", "docs", "--scopes", "read,write"]},
      {"logout", fn opts -> CLI.mcp_logout("docs", codex_opts: opts) end,
       ["mcp", "logout", "docs"]},
      {"remove", fn opts -> CLI.mcp_remove("docs", codex_opts: opts) end,
       ["mcp", "remove", "docs"]}
    ]

    Enum.each(cases, fn {label, fun, expected_argv} ->
      args_path = tmp_path("argv_mcp_#{label}")
      script_path = probe_script(args_path, stdout: "ok\n")
      {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

      assert {:ok, %{success: true}} = fun.(codex_opts)
      assert argv(args_path) == expected_argv
    end)
  end

  defp argv(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end

  defp probe_script(args_path, opts) do
    stdin_path = Keyword.get(opts, :stdin_path)
    stdout = Keyword.get(opts, :stdout, "")

    body = """
    #!/usr/bin/env python3
    import json
    import sys

    ARGS_PATH = #{inspect(args_path)}
    STDIN_PATH = #{if(is_nil(stdin_path), do: "None", else: inspect(stdin_path))}
    STDOUT = #{inspect(stdout)}

    with open(ARGS_PATH, "w", encoding="utf-8") as handle:
        json.dump(sys.argv[1:], handle)

    if STDIN_PATH:
        with open(STDIN_PATH, "w", encoding="utf-8") as handle:
            handle.write(sys.stdin.read())

    sys.stdout.write(STDOUT)
    sys.stdout.flush()
    """

    path = tmp_path("probe")
    File.write!(path, body)
    File.chmod!(path, 0o755)
    on_exit(fn -> File.rm_rf(path) end)
    path
  end

  defp env_probe_script(args_path, env_key) do
    body = """
    #!/usr/bin/env python3
    import json
    import os
    import sys

    ARGS_PATH = #{inspect(args_path)}
    ENV_KEY = #{inspect(env_key)}

    with open(ARGS_PATH, "w", encoding="utf-8") as handle:
        json.dump(sys.argv[1:], handle)

    sys.stdout.write(os.environ.get(ENV_KEY, "missing"))
    sys.stdout.flush()
    """

    path = tmp_path("env_probe")
    File.write!(path, body)
    File.chmod!(path, 0o755)
    on_exit(fn -> File.rm_rf(path) end)
    path
  end

  defp tmp_path(prefix) do
    Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
  end
end
