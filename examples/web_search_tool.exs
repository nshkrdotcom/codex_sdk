# Example: WebSearch Tool Usage
#
# This example demonstrates using the WebSearchTool to perform web searches
# with different providers.
#
# Run: elixir examples/web_search_tool.exs
#
# Environment variables:
#   TAVILY_API_KEY - For Tavily search provider (https://tavily.com)
#   SERPER_API_KEY - For Serper search provider (https://serper.dev)

Mix.install([{:codex_sdk, path: "."}])

alias Codex.Tools
alias Codex.Tools.WebSearchTool

IO.puts("=== WebSearch Tool Example ===\n")

# Reset tools registry
Tools.reset!()

# Note: when using web_search in a Thread, enable `web_search_enabled` or set
# `features.web_search_request=true` in config overrides.

# ============================================================
# Example 1: Mock Provider (No API Key Needed)
# ============================================================
IO.puts("1. Using Mock Provider (for testing)")
IO.puts("-" |> String.duplicate(40))

{:ok, _} = Tools.register(WebSearchTool, provider: :mock)

{:ok, result} =
  Tools.invoke(
    "web_search",
    %{"action" => %{"type" => "search", "query" => "Elixir programming"}},
    %{}
  )

IO.puts("Found #{result["count"]} results:")

for r <- result["results"] do
  IO.puts("")
  IO.puts("  Title: #{r["title"]}")
  IO.puts("  URL: #{r["url"]}")
  IO.puts("  Snippet: #{r["snippet"]}")

  if score = r["score"] do
    IO.puts("  Score: #{score}")
  end
end

IO.puts("")

# ============================================================
# Example 2: With max_results limit
# ============================================================
IO.puts("\n2. Limiting Results")
IO.puts("-" |> String.duplicate(40))

{:ok, limited_result} =
  Tools.invoke(
    "web_search",
    %{"action" => %{"type" => "search", "query" => "GenServer patterns"}, "max_results" => 1},
    %{}
  )

IO.puts("Requested max 1 result, got #{limited_result["count"]} result(s)")
IO.puts("")

# ============================================================
# Example 3: Custom Searcher Callback
# ============================================================
IO.puts("\n3. Using Custom Searcher Callback")
IO.puts("-" |> String.duplicate(40))

# Re-register with a custom searcher
Tools.reset!()

custom_searcher = fn args, _ctx, _meta ->
  query = args["query"]

  {:ok,
   %{
     "count" => 1,
     "results" => [
       %{
         "title" => "Custom result for: #{query}",
         "url" => "https://custom.example.com/search?q=#{URI.encode(query)}",
         "snippet" => "This result came from a custom searcher callback."
       }
     ]
   }}
end

{:ok, _} = Tools.register(WebSearchTool, searcher: custom_searcher)

{:ok, custom_result} =
  Tools.invoke(
    "web_search",
    %{"action" => %{"type" => "search", "query" => "custom search"}},
    %{}
  )

IO.puts("Custom searcher returned:")
IO.puts("  #{inspect(custom_result)}")
IO.puts("")

# ============================================================
# Example 4: Real Provider (if API key available)
# ============================================================

tavily_key = System.get_env("TAVILY_API_KEY")
serper_key = System.get_env("SERPER_API_KEY")

cond do
  tavily_key ->
    IO.puts("\n4. Using Tavily Provider (Live)")
    IO.puts("-" |> String.duplicate(40))

    Tools.reset!()
    {:ok, _} = Tools.register(WebSearchTool, provider: :tavily, api_key: tavily_key)

    case Tools.invoke(
           "web_search",
           %{
             "action" => %{"type" => "search", "query" => "Elixir GenServer patterns 2025"},
             "max_results" => 3
           },
           %{}
         ) do
      {:ok, live_result} ->
        IO.puts("Found #{live_result["count"]} results from Tavily:")

        for r <- live_result["results"] do
          IO.puts("")
          IO.puts("  Title: #{r["title"]}")
          IO.puts("  URL: #{r["url"]}")

          if r["snippet"] do
            snippet = String.slice(r["snippet"], 0, 100)
            IO.puts("  Snippet: #{snippet}...")
          end
        end

      {:error, reason} ->
        IO.puts("Tavily search failed: #{inspect(reason)}")
    end

  serper_key ->
    IO.puts("\n4. Using Serper Provider (Live)")
    IO.puts("-" |> String.duplicate(40))

    Tools.reset!()
    {:ok, _} = Tools.register(WebSearchTool, provider: :serper, api_key: serper_key)

    case Tools.invoke(
           "web_search",
           %{
             "action" => %{"type" => "search", "query" => "Elixir GenServer patterns 2025"},
             "max_results" => 3
           },
           %{}
         ) do
      {:ok, live_result} ->
        IO.puts("Found #{live_result["count"]} results from Serper:")

        for r <- live_result["results"] do
          IO.puts("")
          IO.puts("  Title: #{r["title"]}")
          IO.puts("  URL: #{r["url"]}")

          if r["snippet"] do
            snippet = String.slice(r["snippet"], 0, 100)
            IO.puts("  Snippet: #{snippet}...")
          end
        end

      {:error, reason} ->
        IO.puts("Serper search failed: #{inspect(reason)}")
    end

  true ->
    IO.puts("\n4. Live Provider (Skipped)")
    IO.puts("-" |> String.duplicate(40))
    IO.puts("No API key found. Set TAVILY_API_KEY or SERPER_API_KEY to test live search.")
    IO.puts("")
    IO.puts("Get API keys from:")
    IO.puts("  - Tavily: https://tavily.com")
    IO.puts("  - Serper: https://serper.dev")
end

IO.puts("\n=== Example Complete ===")
