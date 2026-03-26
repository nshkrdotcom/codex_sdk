defmodule Codex.CLISessionTest do
  use ExUnit.Case, async: false

  alias CliSubprocessCore.{RawSession, Transport}
  alias Codex.{CLI, Options}
  alias Codex.CLI.Session

  test "interactive session supports PTY stdin/stdout round trips" do
    args_path = tmp_path("argv_interactive")
    script_path = interactive_probe_script(args_path, exit_immediately?: false)
    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

    assert {:ok, session} =
             CLI.start(["resume", "--last"],
               codex_opts: codex_opts,
               pty: true,
               stdin: true
             )

    assert %Session{} = session
    assert %RawSession{} = raw_session = Map.fetch!(session, :raw_session)
    assert raw_session.transport_module == Transport
    assert raw_session.pty? == true
    assert raw_session.stdin? == true
    assert_receive {:stdout, os_pid, data}, 1_000
    assert os_pid == session.os_pid
    assert data =~ "ready"

    assert :ok = Session.send_input(session, "hello\n")
    assert_receive {:stdout, ^os_pid, data}, 1_000
    assert data =~ "ack:hello"

    assert :ok = Session.close_input(session)

    assert {:ok, result} = Session.collect(session, 1_000)
    assert result.exit_code in [0, 129]
    assert argv(args_path) == ["resume", "--last"]
  end

  test "stop closes a session even when the subprocess ignores SIGINT" do
    args_path = tmp_path("argv_stop")
    script_path = interactive_probe_script(args_path, ignore_sigint?: true)
    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

    assert {:ok, session} =
             CLI.start(["resume", "--last"],
               codex_opts: codex_opts
             )

    assert_receive {:stdout, os_pid, data}, 1_000
    assert os_pid == session.os_pid
    assert data =~ "ready"

    assert :ok = Session.stop(session)
    assert {:ok, result} = Session.collect(session, 1_000)
    refute result.success
  end

  test "interactive wrapper builds base codex argv with global flags" do
    args_path = tmp_path("argv_root")
    script_path = interactive_probe_script(args_path, exit_immediately?: true)
    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

    assert {:ok, session} =
             CLI.interactive("Explain this repo",
               codex_opts: codex_opts,
               cd: "/repo",
               add_dir: ["../shared"],
               image: ["shot.png"],
               no_alt_screen: true,
               search: true
             )

    assert {:ok, %{success: true}} = Session.collect(session, 1_000)

    assert argv(args_path) == [
             "--cd",
             "/repo",
             "--add-dir",
             "../shared",
             "--image",
             "shot.png",
             "--no-alt-screen",
             "--search",
             "Explain this repo"
           ]
  end

  test "interactive wrapper forwards remote app-server flags" do
    args_path = tmp_path("argv_root_remote")
    script_path = interactive_probe_script(args_path, exit_immediately?: true)
    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

    assert {:ok, session} =
             CLI.interactive("Explain this repo",
               codex_opts: codex_opts,
               remote: "ws://127.0.0.1:4500",
               remote_auth_token_env: "CODEX_REMOTE_TOKEN"
             )

    assert {:ok, %{success: true}} = Session.collect(session, 1_000)

    assert argv(args_path) == [
             "--remote",
             "ws://127.0.0.1:4500",
             "--remote-auth-token-env",
             "CODEX_REMOTE_TOKEN",
             "Explain this repo"
           ]
  end

  test "app_server wrapper forwards websocket capability-token flags" do
    args_path = tmp_path("argv_app_server_capability")
    script_path = interactive_probe_script(args_path, exit_immediately?: true)
    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

    assert {:ok, session} =
             CLI.app_server(
               codex_opts: codex_opts,
               ws_auth: :capability_token,
               ws_token_file: "/tmp/codex-token"
             )

    assert {:ok, %{success: true}} = Session.collect(session, 1_000)

    assert argv(args_path) == [
             "app-server",
             "--ws-auth",
             "capability-token",
             "--ws-token-file",
             "/tmp/codex-token"
           ]
  end

  test "app_server wrapper forwards signed bearer websocket flags" do
    args_path = tmp_path("argv_app_server_signed")
    script_path = interactive_probe_script(args_path, exit_immediately?: true)
    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

    assert {:ok, session} =
             CLI.app_server(
               codex_opts: codex_opts,
               ws_auth: :signed_bearer_token,
               ws_shared_secret_file: "/tmp/codex-secret",
               ws_issuer: "issuer",
               ws_audience: "audience",
               ws_max_clock_skew_seconds: 9
             )

    assert {:ok, %{success: true}} = Session.collect(session, 1_000)

    assert argv(args_path) == [
             "app-server",
             "--ws-auth",
             "signed-bearer-token",
             "--ws-shared-secret-file",
             "/tmp/codex-secret",
             "--ws-issuer",
             "issuer",
             "--ws-audience",
             "audience",
             "--ws-max-clock-skew-seconds",
             "9"
           ]
  end

  test "session wrappers build expected argv" do
    cases = [
      {"app_server",
       fn opts ->
         CLI.app_server(codex_opts: opts, listen: "ws://127.0.0.1:8080")
       end, ["app-server", "--listen", "ws://127.0.0.1:8080"]},
      {"cloud", fn opts -> CLI.cloud(codex_opts: opts) end, ["cloud"]},
      {"resume_last", fn opts -> CLI.resume(:last, codex_opts: opts, all: true) end,
       ["resume", "--all", "--last"]},
      {"resume_id", fn opts -> CLI.resume("session-1", codex_opts: opts) end,
       ["resume", "session-1"]},
      {"fork", fn opts -> CLI.fork(:last, codex_opts: opts, all: true) end,
       ["fork", "--all", "--last"]},
      {"mcp_server", fn opts -> CLI.mcp_server(codex_opts: opts) end, ["mcp-server"]}
    ]

    Enum.each(cases, fn {label, fun, expected_argv} ->
      args_path = tmp_path("argv_#{label}")
      script_path = interactive_probe_script(args_path, exit_immediately?: true)
      {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

      assert {:ok, session} = fun.(codex_opts)
      assert {:ok, %{success: true}} = Session.collect(session, 1_000)
      assert argv(args_path) == expected_argv
    end)
  end

  test "resume wrapper forwards include_non_interactive and remote flags" do
    args_path = tmp_path("argv_resume_remote")
    script_path = interactive_probe_script(args_path, exit_immediately?: true)
    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

    assert {:ok, session} =
             CLI.resume(:last,
               codex_opts: codex_opts,
               include_non_interactive: true,
               remote: "ws://127.0.0.1:4500",
               remote_auth_token_env: "CODEX_REMOTE_TOKEN"
             )

    assert {:ok, %{success: true}} = Session.collect(session, 1_000)

    assert argv(args_path) == [
             "resume",
             "--include-non-interactive",
             "--remote",
             "ws://127.0.0.1:4500",
             "--remote-auth-token-env",
             "CODEX_REMOTE_TOKEN",
             "--last"
           ]
  end

  test "fork wrapper forwards remote flags" do
    args_path = tmp_path("argv_fork_remote")
    script_path = interactive_probe_script(args_path, exit_immediately?: true)
    {:ok, codex_opts} = Options.new(%{api_key: "test", codex_path_override: script_path})

    assert {:ok, session} =
             CLI.fork(:last,
               codex_opts: codex_opts,
               remote: "ws://127.0.0.1:4500",
               remote_auth_token_env: "CODEX_REMOTE_TOKEN"
             )

    assert {:ok, %{success: true}} = Session.collect(session, 1_000)

    assert argv(args_path) == [
             "fork",
             "--remote",
             "ws://127.0.0.1:4500",
             "--remote-auth-token-env",
             "CODEX_REMOTE_TOKEN",
             "--last"
           ]
  end

  defp argv(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end

  defp interactive_probe_script(args_path, opts) do
    exit_immediately? = Keyword.get(opts, :exit_immediately?, false)
    ignore_sigint? = Keyword.get(opts, :ignore_sigint?, false)

    body = """
    #!/usr/bin/env python3
    import json
    import signal
    import time
    import sys

    ARGS_PATH = #{inspect(args_path)}
    EXIT_IMMEDIATELY = #{if(exit_immediately?, do: "True", else: "False")}
    IGNORE_SIGINT = #{if(ignore_sigint?, do: "True", else: "False")}

    with open(ARGS_PATH, "w", encoding="utf-8") as handle:
        json.dump(sys.argv[1:], handle)

    sys.stdout.write("ready\\n")
    sys.stdout.flush()

    if EXIT_IMMEDIATELY:
        sys.exit(0)

    if IGNORE_SIGINT:
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        while True:
            time.sleep(1)

    for line in sys.stdin:
        sys.stdout.write("ack:" + line)
        sys.stdout.flush()
        break
    """

    path = tmp_path("interactive_probe")
    File.write!(path, body)
    File.chmod!(path, 0o755)
    on_exit(fn -> File.rm_rf(path) end)
    path
  end

  defp tmp_path(prefix) do
    Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}")
  end
end
