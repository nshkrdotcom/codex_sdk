defmodule Codex.HostedToolsTest do
  use ExUnit.Case, async: false

  alias Codex.Tool
  alias Codex.Tools
  alias Codex.Tools.{ApplyPatchTool, ComputerTool, FileSearchTool, ShellTool}

  setup do
    Tools.reset!()
    Tools.reset_metrics()

    on_exit(fn ->
      Tools.reset!()
      Tools.reset_metrics()
    end)

    :ok
  end

  test "shell tool dispatches to executor with truncation" do
    parent = self()

    executor = fn args, ctx, metadata ->
      send(parent, {:shell_called, args, ctx, metadata})
      {:ok, "123456789"}
    end

    assert ShellTool.metadata()[:name] == "shell"
    assert Tool.metadata(ShellTool)[:name] == "shell"

    {:ok, handle} =
      Tools.register(ShellTool,
        executor: executor,
        timeout_ms: 1000,
        max_output_bytes: 5
      )

    assert handle.name == "shell"
    assert {:ok, _info} = Tools.lookup("shell")
    assert {:ok, "12345"} = Tools.invoke("shell", %{"command" => "ls"}, %{})

    assert_receive {:shell_called, %{"command" => "ls"}, ctx, meta}
    assert ctx.timeout_ms == 1000
    assert meta.max_output_bytes == 5
  end

  test "apply patch tool forwards patch to editor" do
    editor = fn %{"patch" => patch}, _ctx ->
      {:ok, %{applied: patch}}
    end

    assert ApplyPatchTool.metadata()[:name] == "apply_patch"
    assert Tool.metadata(ApplyPatchTool)[:name] == "apply_patch"

    {:ok, handle} = Tools.register(ApplyPatchTool, editor: editor)

    assert handle.name == "apply_patch"
    assert {:ok, _} = Tools.lookup("apply_patch")

    assert {:ok, %{applied: "diff --git"}} =
             Tools.invoke("apply_patch", %{"patch" => "diff --git"}, %{})
  end

  test "computer tool enforces safety hook" do
    deny = fn _args, _ctx -> {:deny, "blocked"} end

    assert ComputerTool.metadata()[:name] == "computer"
    assert Tool.metadata(ComputerTool)[:name] == "computer"

    {:ok, handle} =
      Tools.register(ComputerTool,
        safety: deny,
        executor: fn _, _, _ -> {:ok, %{status: :ran}} end
      )

    assert handle.name == "computer"
    assert {:ok, _} = Tools.lookup("computer")

    assert {:error, {:computer_denied, "blocked"}} =
             Tools.invoke("computer", %{"action" => "click"}, %{})

    allow = fn _args, _ctx -> :ok end

    {:ok, _} =
      Tools.register(ComputerTool,
        name: "computer_allow",
        safety: allow,
        executor: fn _args, _ctx, _meta -> {:ok, %{status: :ran}} end
      )

    assert {:ok, %{status: :ran}} =
             Tools.invoke("computer_allow", %{"action" => "click"}, %{})
  end

  test "file search tool merges config into search arguments" do
    parent = self()

    searcher = fn args, _ctx, metadata ->
      send(parent, {:file_search_called, args, metadata})
      {:ok, %{results: [%{text: args["query"], vector_store_ids: args["vector_store_ids"]}]}}
    end

    assert FileSearchTool.metadata()[:name] == "file_search"
    assert Tool.metadata(FileSearchTool)[:name] == "file_search"

    {:ok, handle} =
      Tools.register(FileSearchTool,
        searcher: searcher,
        vector_store_ids: ["vs_1"],
        filters: %{"tag" => "docs"}
      )

    assert handle.name == "file_search"
    assert {:ok, _} = Tools.lookup("file_search")

    assert {:ok, %{results: [%{text: "hello", vector_store_ids: ["vs_1"]}]}} =
             Tools.invoke("file_search", %{"query" => "hello"}, %{})

    assert_receive {:file_search_called,
                    %{
                      "filters" => %{"tag" => "docs"},
                      "query" => "hello",
                      "vector_store_ids" => ["vs_1"]
                    }, _}
  end
end
