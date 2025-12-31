defmodule Codex.Tools.ShellToolTest do
  use ExUnit.Case, async: false

  alias Codex.Tool
  alias Codex.Tools
  alias Codex.Tools.ShellTool

  setup do
    Tools.reset!()
    Tools.reset_metrics()

    on_exit(fn ->
      Tools.reset!()
      Tools.reset_metrics()
    end)

    :ok
  end

  describe "metadata/0" do
    test "returns valid tool metadata" do
      meta = ShellTool.metadata()
      assert meta.name == "shell"
      assert meta.description == "Execute shell commands"
      assert meta.schema["required"] == ["command"]
      assert meta.schema["properties"]["command"]["type"] == "string"
      assert meta.schema["properties"]["cwd"]["type"] == "string"
      assert meta.schema["properties"]["timeout_ms"]["type"] == "integer"
    end

    test "Tool.metadata/1 returns module metadata" do
      assert Tool.metadata(ShellTool)[:name] == "shell"
    end
  end

  describe "invoke/2 with custom executor" do
    test "executes simple command via custom executor" do
      parent = self()

      executor = fn args, _ctx, _meta ->
        send(parent, {:shell_called, args})
        {:ok, %{"output" => "hello world", "exit_code" => 0}}
      end

      {:ok, _} = Tools.register(ShellTool, executor: executor)

      assert {:ok, result} = Tools.invoke("shell", %{"command" => "echo hello"}, %{})
      assert result["output"] == "hello world"
      assert result["exit_code"] == 0
      assert result["success"] == true

      assert_receive {:shell_called, %{"command" => "echo hello"}}
    end

    test "captures exit code from custom executor" do
      executor = fn _args, _ctx, _meta ->
        {:ok, %{"output" => "error occurred", "exit_code" => 42}}
      end

      {:ok, _} = Tools.register(ShellTool, executor: executor)

      assert {:ok, result} = Tools.invoke("shell", %{"command" => "exit 42"}, %{})
      assert result["exit_code"] == 42
      assert result["success"] == false
    end

    test "truncates large output" do
      large_output = String.duplicate("x", 200)

      executor = fn _args, _ctx, _meta ->
        {:ok, large_output}
      end

      {:ok, _} = Tools.register(ShellTool, executor: executor, max_output_bytes: 50)

      assert {:ok, result} = Tools.invoke("shell", %{"command" => "gen_output"}, %{})
      assert String.ends_with?(result["output"], "... (truncated)")
      assert byte_size(result["output"]) < 200
    end

    test "respects custom cwd from args" do
      parent = self()

      executor = fn args, ctx, _meta ->
        send(parent, {:cwd_check, args, ctx})
        {:ok, %{"output" => "ok", "exit_code" => 0}}
      end

      {:ok, _} = Tools.register(ShellTool, executor: executor)

      {:ok, _} = Tools.invoke("shell", %{"command" => "pwd", "cwd" => "/tmp"}, %{})

      assert_receive {:cwd_check, args, ctx}
      assert args["cwd"] == "/tmp"
      assert ctx.cwd == "/tmp"
    end

    test "respects timeout_ms from context" do
      parent = self()

      executor = fn _args, ctx, _meta ->
        send(parent, {:timeout_check, ctx.timeout_ms})
        {:ok, %{"output" => "ok", "exit_code" => 0}}
      end

      {:ok, _} = Tools.register(ShellTool, executor: executor, timeout_ms: 5000)

      {:ok, _} = Tools.invoke("shell", %{"command" => "test"}, %{})

      assert_receive {:timeout_check, 5000}
    end

    test "timeout_ms in args overrides metadata" do
      parent = self()

      executor = fn _args, ctx, _meta ->
        send(parent, {:timeout_check, ctx.timeout_ms})
        {:ok, %{"output" => "ok", "exit_code" => 0}}
      end

      {:ok, _} = Tools.register(ShellTool, executor: executor, timeout_ms: 5000)

      {:ok, _} = Tools.invoke("shell", %{"command" => "test", "timeout_ms" => 1000}, %{})

      assert_receive {:timeout_check, 1000}
    end

    test "handles executor error" do
      executor = fn _args, _ctx, _meta ->
        {:error, :command_failed}
      end

      {:ok, _} = Tools.register(ShellTool, executor: executor)

      assert {:error, :command_failed} = Tools.invoke("shell", %{"command" => "fail"}, %{})
    end

    test "handles string output from executor" do
      executor = fn _args, _ctx, _meta ->
        {:ok, "just a string"}
      end

      {:ok, _} = Tools.register(ShellTool, executor: executor)

      assert {:ok, result} = Tools.invoke("shell", %{"command" => "test"}, %{})
      assert result["output"] == "just a string"
      assert result["exit_code"] == 0
      assert result["success"] == true
    end

    test "handles bare string return from executor" do
      executor = fn _args, _ctx, _meta ->
        "bare string"
      end

      {:ok, _} = Tools.register(ShellTool, executor: executor)

      assert {:ok, result} = Tools.invoke("shell", %{"command" => "test"}, %{})
      assert result["output"] == "bare string"
    end
  end

  describe "approval integration" do
    test "respects approval callback - allow" do
      approval = fn _cmd, _ctx -> :ok end
      executor = fn _args, _ctx, _meta -> {:ok, "allowed"} end

      {:ok, _} = Tools.register(ShellTool, executor: executor, approval: approval)

      assert {:ok, result} = Tools.invoke("shell", %{"command" => "safe"}, %{})
      assert result["output"] == "allowed"
    end

    test "respects approval callback - deny with reason" do
      approval = fn cmd, _ctx ->
        if String.contains?(cmd, "rm"), do: {:deny, "dangerous"}, else: :ok
      end

      executor = fn _args, _ctx, _meta -> {:ok, "should not run"} end

      {:ok, _} = Tools.register(ShellTool, executor: executor, approval: approval)

      assert {:error, {:approval_denied, "dangerous"}} =
               Tools.invoke("shell", %{"command" => "rm -rf /"}, %{})
    end

    test "respects 3-arity approval callback" do
      parent = self()

      approval = fn cmd, ctx, meta ->
        send(parent, {:approval_check, cmd, ctx, meta})
        :ok
      end

      executor = fn _args, _ctx, _meta -> {:ok, "ok"} end

      {:ok, _} = Tools.register(ShellTool, executor: executor, approval: approval)

      {:ok, _} = Tools.invoke("shell", %{"command" => "test"}, %{user: "admin"})

      assert_receive {:approval_check, "test", ctx, _meta}
      assert ctx.user == "admin"
    end

    test "approval :allow is accepted" do
      approval = fn _cmd, _ctx -> :allow end
      executor = fn _args, _ctx, _meta -> {:ok, "allowed"} end

      {:ok, _} = Tools.register(ShellTool, executor: executor, approval: approval)

      assert {:ok, _} = Tools.invoke("shell", %{"command" => "test"}, %{})
    end

    test "approval {:allow, opts} is accepted" do
      approval = fn _cmd, _ctx -> {:allow, grant_root: "/tmp"} end
      executor = fn _args, _ctx, _meta -> {:ok, "allowed"} end

      {:ok, _} = Tools.register(ShellTool, executor: executor, approval: approval)

      assert {:ok, _} = Tools.invoke("shell", %{"command" => "test"}, %{})
    end

    test "approval false is treated as deny" do
      approval = fn _cmd, _ctx -> false end
      executor = fn _args, _ctx, _meta -> {:ok, "should not run"} end

      {:ok, _} = Tools.register(ShellTool, executor: executor, approval: approval)

      assert {:error, {:approval_denied, :denied}} =
               Tools.invoke("shell", %{"command" => "test"}, %{})
    end

    test "approval :deny atom is handled" do
      approval = fn _cmd, _ctx -> :deny end
      executor = fn _args, _ctx, _meta -> {:ok, "should not run"} end

      {:ok, _} = Tools.register(ShellTool, executor: executor, approval: approval)

      assert {:error, {:approval_denied, :denied}} =
               Tools.invoke("shell", %{"command" => "test"}, %{})
    end
  end

  describe "direct invoke/2" do
    test "invokes with custom executor in context metadata" do
      executor = fn _args, _ctx, _meta ->
        {:ok, "direct call"}
      end

      context = %{metadata: %{executor: executor}}
      args = %{"command" => "test"}

      assert {:ok, result} = ShellTool.invoke(args, context)
      assert result["output"] == "direct call"
    end

    test "respects max_output_bytes in direct invoke" do
      executor = fn _args, _ctx, _meta ->
        {:ok, String.duplicate("a", 100)}
      end

      context = %{metadata: %{executor: executor, max_output_bytes: 20}}
      args = %{"command" => "test"}

      assert {:ok, result} = ShellTool.invoke(args, context)
      assert String.ends_with?(result["output"], "... (truncated)")
    end
  end

  describe "default executor (live)" do
    @tag :live
    test "executes real echo command" do
      {:ok, _} = Tools.register(ShellTool)

      assert {:ok, result} = Tools.invoke("shell", %{"command" => "echo hello"}, %{})
      assert String.contains?(result["output"], "hello")
      assert result["exit_code"] == 0
      assert result["success"] == true
    end

    @tag :live
    test "captures non-zero exit code" do
      {:ok, _} = Tools.register(ShellTool)

      assert {:ok, result} = Tools.invoke("shell", %{"command" => "exit 5"}, %{})
      assert result["exit_code"] == 5
      assert result["success"] == false
    end

    @tag :live
    test "captures stderr in output" do
      {:ok, _} = Tools.register(ShellTool)

      assert {:ok, result} = Tools.invoke("shell", %{"command" => "echo err >&2"}, %{})
      assert String.contains?(result["output"], "err")
    end

    @tag :live
    test "times out on slow command" do
      {:ok, _} = Tools.register(ShellTool, timeout_ms: 100)

      assert {:error, :timeout} = Tools.invoke("shell", %{"command" => "sleep 10"}, %{})
    end

    @tag :live
    test "respects cwd for real command" do
      {:ok, _} = Tools.register(ShellTool)

      assert {:ok, result} = Tools.invoke("shell", %{"command" => "pwd", "cwd" => "/tmp"}, %{})
      assert String.contains?(result["output"], "/tmp")
    end

    @tag :live
    test "handles command with special characters" do
      {:ok, _} = Tools.register(ShellTool)

      assert {:ok, result} =
               Tools.invoke("shell", %{"command" => "echo 'hello world'"}, %{})

      assert String.contains?(result["output"], "hello world")
    end

    @tag :live
    test "handles command with quotes" do
      {:ok, _} = Tools.register(ShellTool)

      assert {:ok, result} =
               Tools.invoke("shell", %{"command" => "echo \"quoted\""}, %{})

      assert String.contains?(result["output"], "quoted")
    end

    @tag :live
    test "truncates real large output" do
      {:ok, _} = Tools.register(ShellTool, max_output_bytes: 50)

      # Generate output larger than 50 bytes
      assert {:ok, result} =
               Tools.invoke("shell", %{"command" => "yes | head -n 100"}, %{})

      assert String.ends_with?(result["output"], "... (truncated)")
    end
  end

  describe "registration" do
    test "registers with default name" do
      {:ok, handle} = Tools.register(ShellTool)
      assert handle.name == "shell"
      assert handle.module == ShellTool
    end

    test "registers with custom name" do
      {:ok, handle} = Tools.register(ShellTool, name: "my_shell")
      assert handle.name == "my_shell"
    end

    test "lookup returns registered tool" do
      {:ok, _} = Tools.register(ShellTool)
      assert {:ok, info} = Tools.lookup("shell")
      assert info.module == ShellTool
    end
  end

  describe "metrics" do
    test "records successful invocation metrics" do
      executor = fn _args, _ctx, _meta -> {:ok, "ok"} end
      {:ok, _} = Tools.register(ShellTool, executor: executor)

      {:ok, _} = Tools.invoke("shell", %{"command" => "test"}, %{})

      metrics = Tools.metrics()
      assert metrics["shell"].success == 1
      assert metrics["shell"].failure == 0
    end

    test "records failed invocation metrics" do
      executor = fn _args, _ctx, _meta -> {:error, :failed} end
      {:ok, _} = Tools.register(ShellTool, executor: executor)

      {:error, _} = Tools.invoke("shell", %{"command" => "test"}, %{})

      metrics = Tools.metrics()
      assert metrics["shell"].failure == 1
      assert metrics["shell"].last_error == :failed
    end
  end
end
