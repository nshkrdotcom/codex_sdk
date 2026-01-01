defmodule Codex.Tools.WebSearchToolTest do
  use ExUnit.Case, async: false

  alias Codex.Options
  alias Codex.Thread
  alias Codex.Thread.Options, as: ThreadOptions
  alias Codex.Tool
  alias Codex.Tools
  alias Codex.Tools.WebSearchTool

  setup do
    Tools.reset!()
    Tools.reset_metrics()

    # Clear env vars that might interfere with tests
    System.delete_env("TAVILY_API_KEY")
    System.delete_env("SERPER_API_KEY")

    on_exit(fn ->
      Tools.reset!()
      Tools.reset_metrics()
      System.delete_env("TAVILY_API_KEY")
      System.delete_env("SERPER_API_KEY")
    end)

    :ok
  end

  describe "metadata/0" do
    test "returns valid tool metadata" do
      meta = WebSearchTool.metadata()
      assert meta.name == "web_search"
      assert meta.description == "Search the web for information"
      assert meta.schema["required"] == nil
      assert meta.schema["properties"]["action"]["type"] == "object"
      assert meta.schema["properties"]["query"]["type"] == "string"
      assert meta.schema["properties"]["type"]["type"] == "string"
      assert meta.schema["properties"]["max_results"]["type"] == "integer"
    end

    test "Tool.metadata/1 returns module metadata" do
      assert Tool.metadata(WebSearchTool)[:name] == "web_search"
    end
  end

  describe "invoke/2 with mock provider" do
    test "returns search results" do
      args = %{"query" => "elixir programming"}
      context = %{metadata: %{provider: :mock}}

      {:ok, result} = WebSearchTool.invoke(args, context)

      assert result["count"] == 2
      assert length(result["results"]) == 2

      first = hd(result["results"])
      assert first["title"] =~ "elixir programming"
      assert first["url"] =~ "example.com"
      assert is_binary(first["snippet"])
      assert is_float(first["score"])
    end

    test "accepts action map for search" do
      args = %{"action" => %{"type" => "search", "query" => "elixir programming"}}
      context = %{metadata: %{provider: :mock}}

      {:ok, result} = WebSearchTool.invoke(args, context)

      assert result["count"] == 2
    end

    test "returns error for unsupported action" do
      args = %{"action" => %{"type" => "open_page", "url" => "https://example.com"}}
      context = %{metadata: %{provider: :mock}}

      assert {:error, {:unsupported_action, "open_page"}} = WebSearchTool.invoke(args, context)
    end

    test "respects max_results from args" do
      args = %{"query" => "test", "max_results" => 1}
      context = %{metadata: %{provider: :mock}}

      {:ok, result} = WebSearchTool.invoke(args, context)

      assert result["count"] == 1
      assert length(result["results"]) == 1
    end

    test "respects max_results from metadata" do
      args = %{"query" => "test"}
      context = %{metadata: %{provider: :mock, max_results: 1}}

      {:ok, result} = WebSearchTool.invoke(args, context)

      assert result["count"] == 1
    end

    test "args max_results overrides metadata" do
      args = %{"query" => "test", "max_results" => 2}
      context = %{metadata: %{provider: :mock, max_results: 1}}

      {:ok, result} = WebSearchTool.invoke(args, context)

      assert result["count"] == 2
    end
  end

  describe "invoke/2 with custom searcher" do
    test "uses custom searcher callback" do
      parent = self()

      searcher = fn args, _ctx, _meta ->
        send(parent, {:search_called, args})
        {:ok, %{"count" => 1, "results" => [%{"title" => args["query"]}]}}
      end

      args = %{"action" => %{"type" => "search", "query" => "test query"}}
      context = %{metadata: %{searcher: searcher}}

      {:ok, result} = WebSearchTool.invoke(args, context)

      assert result["count"] == 1
      assert_receive {:search_called, %{"query" => "test query"}}
    end

    test "searcher takes priority over provider" do
      searcher = fn _args, _ctx, _meta ->
        {:ok, %{"source" => "custom"}}
      end

      args = %{"query" => "test"}
      context = %{metadata: %{searcher: searcher, provider: :mock}}

      {:ok, result} = WebSearchTool.invoke(args, context)

      assert result["source"] == "custom"
    end

    test "handles searcher returning bare value" do
      searcher = fn _args, _ctx, _meta ->
        %{"count" => 0, "results" => []}
      end

      args = %{"query" => "test"}
      context = %{metadata: %{searcher: searcher}}

      {:ok, result} = WebSearchTool.invoke(args, context)

      assert result["count"] == 0
    end

    test "handles searcher error" do
      searcher = fn _args, _ctx, _meta ->
        {:error, :search_failed}
      end

      args = %{"query" => "test"}
      context = %{metadata: %{searcher: searcher}}

      assert {:error, :search_failed} = WebSearchTool.invoke(args, context)
    end
  end

  describe "invoke/2 error handling" do
    test "returns error for missing API key with tavily provider" do
      args = %{"query" => "test"}
      context = %{metadata: %{provider: :tavily}}

      assert {:error, {:missing_api_key, :tavily}} = WebSearchTool.invoke(args, context)
    end

    test "returns error for missing API key with serper provider" do
      args = %{"query" => "test"}
      context = %{metadata: %{provider: :serper}}

      assert {:error, {:missing_api_key, :serper}} = WebSearchTool.invoke(args, context)
    end

    test "returns error for unknown provider" do
      args = %{"query" => "test"}
      context = %{metadata: %{provider: :unknown, api_key: "test"}}

      assert {:error, {:unknown_provider, :unknown}} = WebSearchTool.invoke(args, context)
    end

    test "uses API key from environment for tavily" do
      System.put_env("TAVILY_API_KEY", "test-key")

      # Mock the HTTP client to prevent actual API call
      original_impl = Application.get_env(:codex_sdk, :http_client)
      Application.put_env(:codex_sdk, :http_client, Codex.HTTPClient.Mock)

      on_exit(fn ->
        if original_impl do
          Application.put_env(:codex_sdk, :http_client, original_impl)
        else
          Application.delete_env(:codex_sdk, :http_client)
        end
      end)

      args = %{"query" => "test"}
      context = %{metadata: %{provider: :tavily}}

      # Should not return missing_api_key error
      result = WebSearchTool.invoke(args, context)
      refute match?({:error, {:missing_api_key, _}}, result)
    end
  end

  describe "registration and invocation via Tools" do
    test "registers with default name" do
      {:ok, handle} = Tools.register(WebSearchTool, provider: :mock)
      assert handle.name == "web_search"
      assert handle.module == WebSearchTool
    end

    test "invokes through Tools.invoke" do
      {:ok, _} = Tools.register(WebSearchTool, provider: :mock)

      assert {:ok, result} = Tools.invoke("web_search", %{"query" => "elixir"}, %{})
      assert result["count"] == 2
    end

    test "registers with custom name" do
      {:ok, handle} = Tools.register(WebSearchTool, name: "my_search", provider: :mock)
      assert handle.name == "my_search"
    end

    test "lookup returns registered tool" do
      {:ok, _} = Tools.register(WebSearchTool, provider: :mock)
      assert {:ok, info} = Tools.lookup("web_search")
      assert info.module == WebSearchTool
    end
  end

  describe "enablement gating" do
    test "disabled by default for thread context" do
      {:ok, _} = Tools.register(WebSearchTool, provider: :mock)
      {:ok, thread_opts} = ThreadOptions.new(%{web_search_enabled: false})
      {:ok, codex_opts} = Options.new(%{api_key: "test"})
      thread = Thread.build(codex_opts, thread_opts)

      assert {:error, {:tool_disabled, "web_search"}} =
               Tools.invoke("web_search", %{"query" => "test"}, %{thread: thread})
    end

    test "enabled when thread opts set web_search_enabled" do
      {:ok, _} = Tools.register(WebSearchTool, provider: :mock)
      {:ok, thread_opts} = ThreadOptions.new(%{web_search_enabled: true})
      {:ok, codex_opts} = Options.new(%{api_key: "test"})
      thread = Thread.build(codex_opts, thread_opts)

      assert {:ok, result} = Tools.invoke("web_search", %{"query" => "test"}, %{thread: thread})
      assert result["count"] == 2
    end

    test "enabled when config features.web_search_request is true" do
      {:ok, _} = Tools.register(WebSearchTool, provider: :mock)

      {:ok, thread_opts} =
        ThreadOptions.new(%{
          web_search_enabled: false,
          config: %{"features" => %{"web_search_request" => true}}
        })

      {:ok, codex_opts} = Options.new(%{api_key: "test"})
      thread = Thread.build(codex_opts, thread_opts)

      assert {:ok, result} = Tools.invoke("web_search", %{"query" => "test"}, %{thread: thread})
      assert result["count"] == 2
    end
  end

  describe "metrics" do
    test "records successful invocation metrics" do
      {:ok, _} = Tools.register(WebSearchTool, provider: :mock)

      {:ok, _} = Tools.invoke("web_search", %{"query" => "test"}, %{})

      metrics = Tools.metrics()
      assert metrics["web_search"].success == 1
      assert metrics["web_search"].failure == 0
    end

    test "records failed invocation metrics" do
      {:ok, _} = Tools.register(WebSearchTool, provider: :tavily)

      {:error, _} = Tools.invoke("web_search", %{"query" => "test"}, %{})

      metrics = Tools.metrics()
      assert metrics["web_search"].failure == 1
    end
  end

  describe "direct invoke/2" do
    test "invokes with provider in context metadata" do
      context = %{metadata: %{provider: :mock}}
      args = %{"query" => "test"}

      assert {:ok, result} = WebSearchTool.invoke(args, context)
      assert result["count"] == 2
    end

    test "default provider is tavily (requires API key)" do
      context = %{metadata: %{}}
      args = %{"query" => "test"}

      # Without API key, should fail
      assert {:error, {:missing_api_key, :tavily}} = WebSearchTool.invoke(args, context)
    end
  end

  describe "result formatting" do
    test "includes score when available (mock provider)" do
      args = %{"query" => "test"}
      context = %{metadata: %{provider: :mock}}

      {:ok, result} = WebSearchTool.invoke(args, context)

      first = hd(result["results"])
      assert Map.has_key?(first, "score")
    end

    test "score field is omitted when nil" do
      # Use a custom searcher that returns nil score to test formatting
      custom_searcher = fn _args, _ctx, _meta ->
        {:ok,
         %{
           "count" => 1,
           "results" => [
             %{"title" => "Test", "url" => "http://test.com", "snippet" => "test"}
           ]
         }}
      end

      args = %{"query" => "test"}
      context = %{metadata: %{searcher: custom_searcher}}

      {:ok, result} = WebSearchTool.invoke(args, context)

      first = hd(result["results"])
      assert Map.has_key?(first, "title")
      assert Map.has_key?(first, "url")
      assert Map.has_key?(first, "snippet")
      # When searcher returns formatted results, score may not be present
      refute Map.has_key?(first, "score")
    end
  end

  describe "API key from metadata" do
    test "uses api_key from metadata instead of env" do
      # Mock the HTTP client
      original_impl = Application.get_env(:codex_sdk, :http_client)
      Application.put_env(:codex_sdk, :http_client, Codex.HTTPClient.Mock)

      on_exit(fn ->
        if original_impl do
          Application.put_env(:codex_sdk, :http_client, original_impl)
        else
          Application.delete_env(:codex_sdk, :http_client)
        end
      end)

      args = %{"query" => "test"}
      context = %{metadata: %{provider: :tavily, api_key: "my-api-key"}}

      # Should not fail with missing_api_key
      result = WebSearchTool.invoke(args, context)
      refute match?({:error, {:missing_api_key, _}}, result)
    end
  end
end
