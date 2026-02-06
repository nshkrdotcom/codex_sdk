defmodule Codex.Tools.RegistryTest do
  use ExUnit.Case, async: false

  alias Codex.Tools
  alias Codex.Tools.Registry
  alias Codex.Tools.ShellCommandTool
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

  test "container.exec aliases to shell" do
    executor = fn _args, _ctx, _meta -> {:ok, %{"output" => "ok", "exit_code" => 0}} end
    {:ok, _} = Tools.register(ShellTool, executor: executor)

    assert {:ok, result} = Tools.invoke("container.exec", %{"command" => ["echo", "ok"]}, %{})
    assert result["success"] == true

    assert {:ok, info} = Tools.lookup("container.exec")
    assert info.module == ShellTool
    assert info.name == "shell"
  end

  test "shell_command aliases to shell when not registered" do
    executor = fn _args, _ctx, _meta -> {:ok, %{"output" => "ok", "exit_code" => 0}} end
    {:ok, _} = Tools.register(ShellTool, executor: executor)

    assert {:ok, result} = Tools.invoke("shell_command", %{"command" => ["echo", "ok"]}, %{})
    assert result["success"] == true
  end

  test "shell_command uses shell_command tool when registered" do
    executor = fn _args, _ctx, _meta -> {:ok, %{"output" => "ok", "exit_code" => 0}} end
    {:ok, _} = Tools.register(ShellCommandTool, executor: executor)

    assert {:ok, result} = Tools.invoke("shell_command", %{"command" => "echo ok"}, %{})
    assert result["success"] == true

    assert {:ok, info} = Tools.lookup("shell_command")
    assert info.module == ShellCommandTool
  end

  test "register is atomic when another process claims the name mid-registration" do
    Tools.reset!()
    name = "race_tool"
    registration = %{name: name, module: ShellTool, metadata: %{name: name}}
    parent = self()
    ready_ref = make_ref()
    go_ref = make_ref()

    tasks =
      for _ <- 1..40 do
        Task.async(fn ->
          send(parent, {ready_ref, self()})
          receive do: (^go_ref -> :ok)
          Registry.register(registration)
        end)
      end

    for _ <- 1..40 do
      assert_receive {^ready_ref, _pid}, 1_000
    end

    Enum.each(tasks, fn task ->
      send(task.pid, go_ref)
    end)

    results = Enum.map(tasks, &Task.await(&1, 1_000))

    assert Enum.count(results, &match?({:ok, _}, &1)) == 1

    assert Enum.count(results, &match?({:error, {:already_registered, ^name}}, &1)) == 39
  end
end
