defmodule Codex.HostedToolsTest do
  use ExUnit.Case, async: false

  alias Codex.Tool
  alias Codex.Tools
  alias Codex.Tools.{ApplyPatchTool, ComputerTool, ShellTool, VectorStoreSearchTool}

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

    # ShellTool now returns structured result with exit_code and success
    assert {:ok, result} = Tools.invoke("shell", %{"command" => "ls"}, %{})
    assert result["exit_code"] == 0
    assert result["success"] == true
    # Output is truncated to max_output_bytes
    assert String.starts_with?(result["output"], "12345")
    assert String.ends_with?(result["output"], "... (truncated)")

    assert_receive {:shell_called, %{"command" => "ls"}, ctx, meta}
    assert ctx.timeout_ms == 1000
    assert meta.max_output_bytes == 5
  end

  test "apply patch tool applies unified diffs" do
    tmp_dir = Path.join(System.tmp_dir!(), "apply_patch_hosted_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    assert ApplyPatchTool.metadata()[:name] == "apply_patch"
    assert Tool.metadata(ApplyPatchTool)[:name] == "apply_patch"

    {:ok, handle} = Tools.register(ApplyPatchTool, base_path: tmp_dir)

    assert handle.name == "apply_patch"
    assert {:ok, _} = Tools.lookup("apply_patch")

    patch = """
    --- /dev/null
    +++ b/test.txt
    @@ -0,0 +1 @@
    +hello
    """

    assert {:ok, %{"applied" => 1, "files" => [%{"kind" => "add", "path" => _}]}} =
             Tools.invoke("apply_patch", %{"patch" => patch, "base_path" => tmp_dir}, %{})

    assert File.exists?(Path.join(tmp_dir, "test.txt"))
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

  test "vector store search tool merges config into search arguments" do
    parent = self()

    searcher = fn args, _ctx, metadata ->
      send(parent, {:vector_store_search_called, args, metadata})
      {:ok, %{results: [%{text: args["query"], vector_store_ids: args["vector_store_ids"]}]}}
    end

    assert VectorStoreSearchTool.metadata()[:name] == "vector_store_search"
    assert Tool.metadata(VectorStoreSearchTool)[:name] == "vector_store_search"

    {:ok, handle} =
      Tools.register(VectorStoreSearchTool,
        searcher: searcher,
        vector_store_ids: ["vs_1"],
        filters: %{"tag" => "docs"}
      )

    assert handle.name == "vector_store_search"
    assert {:ok, _} = Tools.lookup("vector_store_search")

    assert {:ok, %{results: [%{text: "hello", vector_store_ids: ["vs_1"]}]}} =
             Tools.invoke("vector_store_search", %{"query" => "hello"}, %{})

    assert_receive {:vector_store_search_called,
                    %{
                      "filters" => %{"tag" => "docs"},
                      "query" => "hello",
                      "vector_store_ids" => ["vs_1"]
                    }, _}
  end
end
