# Prompt 08: WebSearch Hosted Tool Implementation

**Target Version:** 0.4.5
**Date:** 2025-12-30
**Depends On:** None (standalone)

## Objective

Implement a WebSearch hosted tool for performing web searches and retrieving results.

## Required Reading

1. **Canonical Implementation:**
   - `codex/codex-rs/core/src/tools/handlers/web.rs` - Web tool handler
   - `openai-agents-python/src/agents/tool.py` - Python WebSearchTool

2. **Elixir SDK:**
   - `lib/codex/tools/hosted_tools.ex` - Current structure
   - `lib/codex/tool.ex` - Tool behavior
   - `lib/codex/http_client.ex` - HTTP client (if exists)

## Implementation Tasks

### 1. Implement `Codex.Tools.WebSearchTool`

Create `lib/codex/tools/web_search_tool.ex`:

```elixir
defmodule Codex.Tools.WebSearchTool do
  @moduledoc """
  Hosted tool for performing web searches.

  ## Configuration

  Requires a search provider to be configured. Supported providers:
  - `:tavily` - Tavily Search API (requires TAVILY_API_KEY)
  - `:serper` - Serper API (requires SERPER_API_KEY)
  - `:mock` - Mock provider for testing

  ## Options
    * `:provider` - Search provider (default: :tavily)
    * `:api_key` - API key (or from environment)
    * `:max_results` - Maximum results (default: 10)
    * `:include_raw` - Include raw response (default: false)
  """

  @behaviour Codex.Tool

  @impl true
  def metadata do
    %{
      name: "web_search",
      description: "Search the web for information",
      schema: %{
        "type" => "object",
        "properties" => %{
          "query" => %{
            "type" => "string",
            "description" => "The search query"
          },
          "max_results" => %{
            "type" => "integer",
            "description" => "Maximum number of results (default: 10)"
          }
        },
        "required" => ["query"],
        "additionalProperties" => false
      }
    }
  end

  @impl true
  def invoke(args, context) do
    query = Map.fetch!(args, "query")
    max_results = Map.get(args, "max_results", 10)
    provider = context[:provider] || :tavily

    with {:ok, api_key} <- get_api_key(provider, context),
         {:ok, results} <- search(provider, query, max_results, api_key) do
      {:ok, format_results(results)}
    end
  end

  defp get_api_key(:mock, _context), do: {:ok, nil}

  defp get_api_key(provider, context) do
    key = context[:api_key] || get_env_key(provider)

    if key do
      {:ok, key}
    else
      {:error, {:missing_api_key, provider}}
    end
  end

  defp get_env_key(:tavily), do: System.get_env("TAVILY_API_KEY")
  defp get_env_key(:serper), do: System.get_env("SERPER_API_KEY")
  defp get_env_key(_), do: nil

  defp search(:mock, query, max_results, _api_key) do
    results = [
      %{
        title: "Mock Result 1 for #{query}",
        url: "https://example.com/1",
        snippet: "This is a mock search result for testing.",
        score: 0.95
      },
      %{
        title: "Mock Result 2 for #{query}",
        url: "https://example.com/2",
        snippet: "Another mock result with relevant content.",
        score: 0.85
      }
    ]

    {:ok, Enum.take(results, max_results)}
  end

  defp search(:tavily, query, max_results, api_key) do
    url = "https://api.tavily.com/search"

    body = Jason.encode!(%{
      api_key: api_key,
      query: query,
      max_results: max_results,
      include_answer: false,
      include_raw_content: false
    })

    headers = [{"Content-Type", "application/json"}]

    case http_client().post(url, body, headers) do
      {:ok, %{status: 200, body: resp_body}} ->
        parse_tavily_response(resp_body)

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {:api_error, status, resp_body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp search(:serper, query, max_results, api_key) do
    url = "https://google.serper.dev/search"

    body = Jason.encode!(%{
      q: query,
      num: max_results
    })

    headers = [
      {"Content-Type", "application/json"},
      {"X-API-KEY", api_key}
    ]

    case http_client().post(url, body, headers) do
      {:ok, %{status: 200, body: resp_body}} ->
        parse_serper_response(resp_body)

      {:ok, %{status: status, body: resp_body}} ->
        {:error, {:api_error, status, resp_body}}

      {:error, reason} ->
        {:error, {:request_failed, reason}}
    end
  end

  defp search(provider, _query, _max_results, _api_key) do
    {:error, {:unknown_provider, provider}}
  end

  defp parse_tavily_response(body) do
    case Jason.decode(body) do
      {:ok, %{"results" => results}} ->
        parsed = Enum.map(results, fn r ->
          %{
            title: r["title"],
            url: r["url"],
            snippet: r["content"],
            score: r["score"]
          }
        end)
        {:ok, parsed}

      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end

  defp parse_serper_response(body) do
    case Jason.decode(body) do
      {:ok, %{"organic" => results}} ->
        parsed = Enum.map(results, fn r ->
          %{
            title: r["title"],
            url: r["link"],
            snippet: r["snippet"],
            score: nil
          }
        end)
        {:ok, parsed}

      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end

  defp format_results(results) do
    %{
      "count" => length(results),
      "results" => Enum.map(results, fn r ->
        result = %{
          "title" => r.title,
          "url" => r.url,
          "snippet" => r.snippet
        }

        if r.score do
          Map.put(result, "score", r.score)
        else
          result
        end
      end)
    }
  end

  defp http_client do
    Application.get_env(:codex_sdk, :http_client, Codex.HTTPClient)
  end
end
```

### 2. Create HTTP Client Abstraction

Create `lib/codex/http_client.ex` if not present:

```elixir
defmodule Codex.HTTPClient do
  @moduledoc """
  HTTP client abstraction for making HTTP requests.
  """

  @callback get(url :: String.t(), headers :: keyword()) ::
              {:ok, map()} | {:error, term()}
  @callback post(url :: String.t(), body :: String.t(), headers :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Performs an HTTP GET request.
  """
  def get(url, headers \\ []) do
    impl().get(url, headers)
  end

  @doc """
  Performs an HTTP POST request.
  """
  def post(url, body, headers \\ []) do
    impl().post(url, body, headers)
  end

  defp impl do
    Application.get_env(:codex_sdk, :http_client_impl, Codex.HTTPClient.Req)
  end
end

defmodule Codex.HTTPClient.Req do
  @moduledoc """
  HTTP client implementation using Req.
  """

  @behaviour Codex.HTTPClient

  @impl true
  def get(url, headers) do
    case Req.get(url, headers: headers) do
      {:ok, %Req.Response{status: status, body: body}} ->
        {:ok, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def post(url, body, headers) do
    case Req.post(url, body: body, headers: headers) do
      {:ok, %Req.Response{status: status, body: body}} ->
        {:ok, %{status: status, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

defmodule Codex.HTTPClient.Mock do
  @moduledoc """
  Mock HTTP client for testing.
  """

  @behaviour Codex.HTTPClient

  @impl true
  def get(_url, _headers) do
    {:ok, %{status: 200, body: "{}"}}
  end

  @impl true
  def post(_url, _body, _headers) do
    {:ok, %{status: 200, body: "{\"results\": []}"}}
  end
end
```

### 3. Register in HostedTools

Update `lib/codex/tools/hosted_tools.ex`:

```elixir
def web_search(opts \\ []) do
  %{
    module: Codex.Tools.WebSearchTool,
    name: "web_search",
    opts: opts
  }
end

def all do
  [shell(), apply_patch(), file_search(), web_search()]
end
```

## Test Requirements (TDD)

### Unit Tests (`test/codex/tools/web_search_tool_test.exs`)

```elixir
defmodule Codex.Tools.WebSearchToolTest do
  use ExUnit.Case, async: true

  describe "metadata/0" do
    test "returns valid tool metadata" do
      meta = Codex.Tools.WebSearchTool.metadata()
      assert meta.name == "web_search"
      assert meta.schema["required"] == ["query"]
    end
  end

  describe "invoke/2 with mock provider" do
    test "returns search results" do
      args = %{"query" => "elixir programming"}
      context = %{provider: :mock}
      {:ok, result} = Codex.Tools.WebSearchTool.invoke(args, context)

      assert result["count"] == 2
      assert length(result["results"]) == 2

      first = hd(result["results"])
      assert first["title"] =~ "elixir programming"
      assert first["url"] =~ "example.com"
      assert is_binary(first["snippet"])
    end

    test "respects max_results" do
      args = %{"query" => "test", "max_results" => 1}
      context = %{provider: :mock}
      {:ok, result} = Codex.Tools.WebSearchTool.invoke(args, context)

      assert result["count"] == 1
    end
  end

  describe "invoke/2 error handling" do
    test "returns error for missing API key" do
      args = %{"query" => "test"}
      context = %{provider: :tavily}  # No API key

      # Clear env var if set
      System.delete_env("TAVILY_API_KEY")

      assert {:error, {:missing_api_key, :tavily}} =
        Codex.Tools.WebSearchTool.invoke(args, context)
    end

    test "returns error for unknown provider" do
      args = %{"query" => "test"}
      context = %{provider: :unknown, api_key: "test"}

      assert {:error, {:unknown_provider, :unknown}} =
        Codex.Tools.WebSearchTool.invoke(args, context)
    end
  end
end
```

### Integration Tests

```elixir
@tag :live
@tag :requires_api_key
describe "WebSearch tool (live)" do
  @describetag skip: !System.get_env("TAVILY_API_KEY")

  test "searches with Tavily" do
    Codex.Tools.register(Codex.Tools.WebSearchTool)

    {:ok, result} = Codex.Tools.invoke(
      "web_search",
      %{"query" => "Elixir programming language", "max_results" => 3},
      %{provider: :tavily}
    )

    assert result["count"] > 0
    assert length(result["results"]) <= 3
  end
end
```

## Verification Criteria

1. [ ] All tests pass: `mix test test/codex/tools/web_search_tool_test.exs`
2. [ ] No warnings
3. [ ] No dialyzer errors
4. [ ] No credo issues
5. [ ] Example works: create `examples/web_search_tool.exs`
6. [ ] `examples/run_all.sh` passes (mock provider for CI)

## Update Requirements

### CHANGELOG.md

Add to the existing `## [0.4.5] - 2025-12-30` section:
```markdown
- WebSearch hosted tool with `Codex.Tools.WebSearchTool`
- Support for Tavily and Serper search providers
- HTTP client abstraction for testability
- Mock provider for testing without API keys
```

### mix.exs

Ensure `req` dependency is present:
```elixir
{:req, "~> 0.4"}
```

### Examples

Create `examples/web_search_tool.exs`:
```elixir
# Example: WebSearch Tool Usage
# Run: elixir examples/web_search_tool.exs

Mix.install([{:codex_sdk, path: "."}])

# Register web search tool
{:ok, _} = Codex.Tools.register(Codex.Tools.WebSearchTool)

# Search with mock provider (no API key needed)
{:ok, result} = Codex.Tools.invoke(
  "web_search",
  %{"query" => "Elixir programming"},
  %{provider: :mock}
)

IO.puts("Found #{result["count"]} results:")
for r <- result["results"] do
  IO.puts("\n  #{r["title"]}")
  IO.puts("  #{r["url"]}")
  IO.puts("  #{r["snippet"]}")
end

# With real provider (requires API key)
if api_key = System.get_env("TAVILY_API_KEY") do
  {:ok, result} = Codex.Tools.invoke(
    "web_search",
    %{"query" => "Elixir GenServer patterns", "max_results" => 5},
    %{provider: :tavily, api_key: api_key}
  )

  IO.puts("\n\nReal search results:")
  for r <- result["results"] do
    IO.puts("\n  #{r["title"]}")
    IO.puts("  #{r["url"]}")
  end
else
  IO.puts("\n\nSkipping real search (TAVILY_API_KEY not set)")
end
```

### README.md

Add WebSearch tool section under Hosted Tools.

### Environment Variables

Document required environment variables:
- `TAVILY_API_KEY` - For Tavily search provider
- `SERPER_API_KEY` - For Serper search provider
