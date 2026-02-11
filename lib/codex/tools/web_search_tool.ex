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

  alias Codex.Config.Defaults
  alias Codex.HTTPClient
  alias Codex.Tools.Hosted

  @default_max_results Defaults.web_search_max_results()

  @impl true
  def metadata do
    %{
      name: "web_search",
      description: "Search the web for information",
      enabled?: &enabled?/2,
      schema: %{
        "type" => "object",
        "properties" => %{
          "action" => %{
            "type" => "object",
            "properties" => %{
              "type" => %{
                "type" => "string",
                "description" => "Action type (search, open_page, find_in_page)"
              },
              "query" => %{"type" => "string"},
              "url" => %{"type" => "string"},
              "pattern" => %{"type" => "string"}
            },
            "additionalProperties" => false
          },
          "query" => %{
            "type" => "string",
            "description" => "The search query (legacy)"
          },
          "type" => %{
            "type" => "string",
            "description" => "Action type (search, open_page, find_in_page)"
          },
          "max_results" => %{
            "type" => "integer",
            "description" => "Maximum number of results (default: 10)"
          }
        },
        "additionalProperties" => true
      }
    }
  end

  @impl true
  def invoke(args, context) do
    metadata = Map.get(context, :metadata, %{})

    # Check for custom searcher callback first (for backwards compatibility)
    case Hosted.callback(metadata, :searcher) do
      fun when is_function(fun) ->
        invoke_with_searcher(fun, ensure_query_arg(args), context, metadata)

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
    with {:ok, action} <- normalize_action(args) do
      case action.type do
        "search" -> perform_search(action, args, metadata)
        other -> {:error, {:unsupported_action, other}}
      end
    end
  end

  defp perform_search(action, args, metadata) do
    max_results = resolve_max_results(args, metadata)
    provider = resolve_provider(metadata)

    with {:ok, api_key} <- get_api_key(provider, metadata),
         {:ok, results} <- search(provider, action.query, max_results, api_key) do
      {:ok, format_results(results)}
    end
  end

  defp resolve_max_results(args, metadata) do
    Map.get(args, "max_results") ||
      Map.get(args, "maxResults") ||
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

    case HTTPClient.post(url, body, headers) do
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

    case HTTPClient.post(url, body, headers) do
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

  defp enabled?(context, _metadata) do
    case Map.get(context, :thread) do
      %{thread_opts: %{web_search_mode: mode}} when mode in [:cached, :live] ->
        true

      %{thread_opts: %{web_search_mode: :disabled}} ->
        false

      %{thread_opts: %{web_search_enabled: true}} ->
        true

      %{thread_opts: opts} ->
        feature_enabled_from_config(opts)

      nil ->
        true

      _ ->
        false
    end
  end

  defp feature_enabled_from_config(%{config: %{"features" => %{"web_search_request" => value}}})
       when is_boolean(value),
       do: value

  defp feature_enabled_from_config(%{config: %{"web_search" => mode}})
       when mode in ["cached", "live", :cached, :live],
       do: true

  defp feature_enabled_from_config(%{config: %{"web_search" => mode}})
       when mode in ["disabled", :disabled],
       do: false

  defp feature_enabled_from_config(%{config: %{web_search: mode}})
       when mode in ["cached", "live", :cached, :live],
       do: true

  defp feature_enabled_from_config(%{config: %{web_search: mode}})
       when mode in ["disabled", :disabled],
       do: false

  defp feature_enabled_from_config(_opts), do: false

  defp normalize_action(args) do
    action = Map.get(args, "action") || Map.get(args, :action)
    type = Map.get(args, "type") || Map.get(args, :type)
    query = Map.get(args, "query") || Map.get(args, :query)

    cond do
      is_map(action) ->
        parse_action(action)

      is_binary(type) ->
        parse_action(args)

      is_binary(query) ->
        {:ok, %{type: "search", query: query}}

      true ->
        {:error, {:missing_argument, :query}}
    end
  end

  defp parse_action(action) when is_map(action) do
    raw_type = fetch_action_value(action, :type)
    type = normalize_action_type(raw_type)

    parse_action_by_type(type, action)
  end

  defp parse_action_by_type("search", action) do
    case fetch_action_string(action, :query) do
      {:ok, query} -> {:ok, %{type: "search", query: query}}
      :error -> {:error, {:missing_argument, :query}}
    end
  end

  defp parse_action_by_type("open_page", action) do
    case fetch_action_string(action, :url) do
      {:ok, url} -> {:ok, %{type: "open_page", url: url}}
      :error -> {:error, {:missing_argument, :url}}
    end
  end

  defp parse_action_by_type("find_in_page", action) do
    with {:ok, url} <- fetch_action_string(action, :url),
         {:ok, pattern} <- fetch_action_string(action, :pattern) do
      {:ok, %{type: "find_in_page", url: url, pattern: pattern}}
    else
      _ -> {:error, {:missing_argument, :pattern}}
    end
  end

  defp parse_action_by_type(nil, _action), do: {:error, {:missing_argument, :type}}
  defp parse_action_by_type(other, _action), do: {:error, {:unsupported_action, other}}

  defp normalize_action_type(nil), do: nil

  defp normalize_action_type(type) when is_binary(type) do
    type
    |> Macro.underscore()
    |> String.downcase()
  end

  defp normalize_action_type(other), do: to_string(other) |> normalize_action_type()

  defp ensure_query_arg(%{} = args) do
    case fetch_action_string(args, :query) do
      {:ok, _query} ->
        args

      :error ->
        maybe_put_query(args)
    end
  end

  defp maybe_put_query(args) do
    case Map.get(args, "action") || Map.get(args, :action) do
      %{} = action ->
        type = fetch_action_value(action, :type)

        case fetch_action_string(action, :query) do
          {:ok, query} when is_binary(type) -> Map.put(args, "query", query)
          _ -> args
        end

      _ ->
        args
    end
  end

  defp fetch_action_value(action, key) do
    Map.get(action, key) || Map.get(action, to_string(key))
  end

  defp fetch_action_string(action, key) do
    case fetch_action_value(action, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _ -> :error
    end
  end
end
