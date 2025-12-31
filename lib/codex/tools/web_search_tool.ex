defmodule Codex.Tools.WebSearchTool do
  @moduledoc """
  Hosted tool for performing web searches.

  ## Overview

  WebSearchTool provides web search functionality with support for multiple
  search providers. It can be used standalone or registered in the tool registry.

  ## Configuration

  Requires a search provider to be configured. Supported providers:

    * `:tavily` - Tavily Search API (requires `TAVILY_API_KEY`)
    * `:serper` - Serper API (requires `SERPER_API_KEY`)
    * `:mock` - Mock provider for testing (no API key needed)
    * Custom callback via `:searcher` option

  ## Options

  Options can be passed during registration or via context metadata:

    * `:provider` - Search provider (default: `:tavily`)
    * `:api_key` - API key (or from environment variable)
    * `:max_results` - Maximum results to return (default: 10)
    * `:searcher` - Custom search callback function (overrides provider)

  ## Usage

  ### With Mock Provider (Testing)

      {:ok, _} = Codex.Tools.register(Codex.Tools.WebSearchTool,
        provider: :mock
      )

      {:ok, result} = Codex.Tools.invoke("web_search", %{"query" => "elixir"}, %{})
      # => %{"count" => 2, "results" => [...]}

  ### With Tavily Provider

      {:ok, _} = Codex.Tools.register(Codex.Tools.WebSearchTool,
        provider: :tavily,
        api_key: System.get_env("TAVILY_API_KEY")
      )

      {:ok, result} = Codex.Tools.invoke("web_search",
        %{"query" => "Elixir programming", "max_results" => 5},
        %{}
      )

  ### With Custom Searcher

      searcher = fn args, _ctx, _meta ->
        {:ok, %{"count" => 1, "results" => [%{"title" => args["query"]}]}}
      end

      {:ok, _} = Codex.Tools.register(Codex.Tools.WebSearchTool,
        searcher: searcher
      )

  ## Environment Variables

    * `TAVILY_API_KEY` - API key for Tavily search provider
    * `SERPER_API_KEY` - API key for Serper search provider

  """

  @behaviour Codex.Tool

  alias Codex.Tools.Hosted

  @default_max_results 10

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
    metadata = Map.get(context, :metadata, %{})

    # Check for custom searcher callback first (for backwards compatibility)
    case Hosted.callback(metadata, :searcher) do
      fun when is_function(fun) ->
        invoke_with_searcher(fun, args, context, metadata)

      nil ->
        invoke_with_provider(args, context, metadata)
    end
  end

  defp invoke_with_searcher(fun, args, context, metadata) do
    case Hosted.safe_call(fun, args, context, metadata) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
      other -> {:ok, other}
    end
  end

  defp invoke_with_provider(args, _context, metadata) do
    query = Map.fetch!(args, "query")
    max_results = resolve_max_results(args, metadata)
    provider = resolve_provider(metadata)

    with {:ok, api_key} <- get_api_key(provider, metadata),
         {:ok, results} <- search(provider, query, max_results, api_key) do
      {:ok, format_results(results)}
    end
  end

  defp resolve_max_results(args, metadata) do
    Map.get(args, "max_results") ||
      Hosted.metadata_value(metadata, :max_results, @default_max_results)
  end

  defp resolve_provider(metadata) do
    Hosted.metadata_value(metadata, :provider, :tavily)
  end

  defp get_api_key(:mock, _metadata), do: {:ok, nil}

  defp get_api_key(provider, metadata) do
    key = Hosted.metadata_value(metadata, :api_key) || get_env_key(provider)

    if key do
      {:ok, key}
    else
      {:error, {:missing_api_key, provider}}
    end
  end

  defp get_env_key(:tavily), do: System.get_env("TAVILY_API_KEY")
  defp get_env_key(:serper), do: System.get_env("SERPER_API_KEY")
  defp get_env_key(_), do: nil

  # Mock provider for testing
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

  # Tavily search provider
  defp search(:tavily, query, max_results, api_key) do
    url = "https://api.tavily.com/search"

    body =
      Jason.encode!(%{
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

  # Serper search provider
  defp search(:serper, query, max_results, api_key) do
    url = "https://google.serper.dev/search"

    body =
      Jason.encode!(%{
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

  defp parse_tavily_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} ->
        parse_tavily_response(decoded)

      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end

  defp parse_tavily_response(%{"results" => results}) when is_list(results) do
    parsed =
      Enum.map(results, fn r ->
        %{
          title: r["title"],
          url: r["url"],
          snippet: r["content"],
          score: r["score"]
        }
      end)

    {:ok, parsed}
  end

  defp parse_tavily_response(response) do
    {:error, {:unexpected_response, response}}
  end

  defp parse_serper_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} ->
        parse_serper_response(decoded)

      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end

  defp parse_serper_response(%{"organic" => results}) when is_list(results) do
    parsed =
      Enum.map(results, fn r ->
        %{
          title: r["title"],
          url: r["link"],
          snippet: r["snippet"],
          score: nil
        }
      end)

    {:ok, parsed}
  end

  defp parse_serper_response(response) do
    {:error, {:unexpected_response, response}}
  end

  defp format_results(results) do
    %{
      "count" => length(results),
      "results" =>
        Enum.map(results, fn r ->
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
