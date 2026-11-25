defmodule Codex.RuntimeExecRenderTest do
  use ExUnit.Case, async: true

  alias Codex.{Exec, Options, Runtime, Thread}

  test "renders Codex-native exec flags without resolving or spawning the CLI" do
    {:ok, codex_opts} =
      Options.new(%{
        api_key: "test-key",
        base_url: "https://api.openai.com/v1",
        model: "gpt-6-luna",
        execution_surface: [
          surface_kind: :local_subprocess,
          observability: %{suite: :promotion_path}
        ]
      })

    {:ok, thread_opts} =
      Thread.Options.new(%{
        sandbox: :read_only,
        ephemeral: true,
        ignore_user_config: true,
        ignore_rules: true,
        additional_directories: ["/tmp/docs"],
        skip_git_repo_check: true,
        skills_enabled: false,
        web_search_mode: :disabled,
        working_directory: "/tmp/work"
      })

    thread = Thread.build(codex_opts, thread_opts)

    {:ok, exec_opts} =
      Exec.Options.new(%{
        codex_opts: codex_opts,
        thread: thread,
        env: %{"CODEX_TEST_RENDER" => "1"},
        clear_env?: true,
        output_schema_path: "schema.json"
      })

    {:ok, render} = Runtime.Exec.render_for_test(exec_opts: exec_opts, input: "hello")

    assert render.provider == :codex
    assert render.stdin == "hello"
    assert render.execution_surface.observability == %{suite: :promotion_path}
    assert render.env["CODEX_TEST_RENDER"] == "1"
    assert render.clear_env? == true
    assert render.provider_native.sandbox == :read_only
    assert render.provider_native.ephemeral == true
    assert render.provider_native.ignore_user_config == true
    assert render.provider_native.ignore_rules == true
    assert render.provider_native.additional_directories == ["/tmp/docs"]
    assert render.provider_native.skip_git_repo_check == true
    assert render.provider_native.output_schema == "schema.json"

    args = render.args
    assert Enum.take(args, 2) == ["exec", "--json"]
    assert flag_value(args, "--model") == "gpt-6-luna"
    assert flag_value(args, "--sandbox") == "read-only"
    assert "--ephemeral" in args
    assert "--ignore-user-config" in args
    assert "--ignore-rules" in args
    assert flag_value(args, "--cd") == "/tmp/work"
    assert repeated_values(args, "--add-dir") == ["/tmp/docs"]
    assert "--skip-git-repo-check" in args
    assert flag_value(args, "--output-schema") == "schema.json"
    assert "features.skills=false" in repeated_values(args, "--config")
    assert ~s(web_search="disabled") in repeated_values(args, "--config")
  end

  defp flag_value(args, flag) do
    case Enum.find_index(args, &(&1 == flag)) do
      nil -> nil
      idx -> Enum.at(args, idx + 1)
    end
  end

  defp repeated_values(args, flag) do
    args
    |> Enum.with_index()
    |> Enum.filter(fn {value, _index} -> value == flag end)
    |> Enum.map(fn {_value, index} -> Enum.at(args, index + 1) end)
  end

  test "remote exec omits inferred local model and config on fresh and resumed runs" do
    {:ok, codex_opts} = Options.new(%{api_key: "test", model: "gpt-6-luna"})

    {:ok, thread_opts} =
      Thread.Options.new(%{remote: "ws://127.0.0.1:4500", remote_auth_token_env: "REMOTE_TOKEN"})

    thread = Thread.build(codex_opts, thread_opts)
    {:ok, exec_opts} = Exec.Options.new(%{codex_opts: codex_opts, thread: thread})
    assert {:ok, render} = Runtime.Exec.render_for_test(exec_opts: exec_opts, input: "hello")

    assert render.args == [
             "exec",
             "--json",
             "--remote",
             "ws://127.0.0.1:4500",
             "--remote-auth-token-env",
             "REMOTE_TOKEN"
           ]

    assert render.config_values == []
    refute Map.has_key?(render.env, "CODEX_API_KEY")
    thread_id = "00000000-0000-4000-8000-000000000001"
    resumed = %{exec_opts | thread: %{thread | thread_id: thread_id}}
    assert {:ok, resumed_render} = Runtime.Exec.render_for_test(exec_opts: resumed, input: "next")
    assert resumed_render.args == render.args ++ ["resume", thread_id]

    sourced = %{
      resumed
      | thread: %{resumed.thread | thread_opts: %{thread_opts | thread_source: :user}}
    }

    assert {:error, {:remote_exec_unsupported_option, :thread_source}} =
             Runtime.Exec.render_for_test(exec_opts: sourced)

    assert {:error, {:remote_exec_unsupported_option, :ephemeral}} =
             Runtime.Exec.render_for_test(
               exec_opts: %{exec_opts | turn_opts: %{ephemeral: false}}
             )

    invalid = %{exec_opts | thread: %{thread | resume: :last}}

    assert {:error, :remote_exec_requires_new_or_resume_by_id} =
             Runtime.Exec.render_for_test(exec_opts: invalid)

    invalid = %{exec_opts | output_schema_path: "schema.json"}

    assert {:error, {:remote_exec_unsupported_option, :output_schema}} =
             Runtime.Exec.render_for_test(exec_opts: invalid)
  end

  test "remote exec rejects malformed addresses, unsafe authentication, and local controls" do
    {:ok, opts} = Options.new(%{})

    cases = [
      {%{remote: "https://example.test:443"}, :invalid_remote_address},
      {%{remote: "ws://:4500"}, :invalid_remote_address},
      {%{remote: "wss://example.test"}, :invalid_remote_address},
      {%{remote: "wss://user:synthetic@example.test:443"}, :invalid_remote_address},
      {%{remote: "ws://example.test:4500", remote_auth_token_env: "REMOTE_TOKEN"},
       :invalid_remote_auth_transport},
      {%{remote: "unix:///tmp/fixture.sock", remote_auth_token_env: "REMOTE_TOKEN"},
       :invalid_remote_auth_transport},
      {%{remote: "ws://localhost:4500", remote_auth_token_env: "BAD-NAME"},
       :invalid_remote_auth_token_env},
      {%{remote: "ws://localhost:4500", ephemeral: false},
       {:remote_exec_unsupported_option, :ephemeral}},
      {%{remote: "ws://localhost:4500", skills_enabled: false},
       {:remote_exec_unsupported_option, :derived_config}}
    ]

    for {attrs, reason} <- cases do
      {:ok, thread_opts} = Thread.Options.new(attrs)

      {:ok, exec_opts} =
        Exec.Options.new(%{codex_opts: opts, thread: Thread.build(opts, thread_opts)})

      assert {:error, ^reason} = Runtime.Exec.render_for_test(exec_opts: exec_opts)
    end
  end

  test "local exec forwards source on new thread and explicit cyber program on resume" do
    {:ok, opts} = Options.new(%{api_key: "test"})
    {:ok, thread_opts} = Thread.Options.new(%{thread_source: :user})
    thread = Thread.build(opts, thread_opts)

    {:ok, exec_opts} =
      Exec.Options.new(%{
        codex_opts: opts,
        thread: thread,
        turn_opts: %{cyber_access_program: :daybreak_blue}
      })

    assert {:ok, render} = Runtime.Exec.render_for_test(exec_opts: exec_opts)
    assert flag_value(render.args, "--thread-source") == "user"
    assert flag_value(render.args, "--cyber-access-program") == "daybreak_blue"

    assert {:ok, resumed} =
             Runtime.Exec.render_for_test(
               exec_opts: %{exec_opts | thread: %{thread | thread_id: "id"}}
             )

    refute "--thread-source" in resumed.args
    assert flag_value(resumed.args, "--cyber-access-program") == "daybreak_blue"
    refute "--cd" in resumed.args
    refute "--sandbox" in resumed.args
  end
end
