defmodule Codex.Tools.FileSearchTool do
  @moduledoc """
  Hosted tool for searching files by name pattern and content.

  This tool provides local filesystem search capabilities using glob patterns
  for file discovery and optional fixed-string content matching.

  ## Options

  Options can be passed during registration or via context:

    * `:base_path` - Base directory for search (default: cwd)
    * `:max_results` - Maximum results to return (default: 100)
    * `:include_hidden` - Include hidden files (default: false)
    * `:case_sensitive` - Case-sensitive matching (default: true)

  ## Usage

  ### Direct Invocation

      args = %{"pattern" => "**/*.ex", "base_path" => "/project"}
      {:ok, result} = Codex.Tools.FileSearchTool.invoke(args, %{})
      # => %{"count" => 42, "files" => [%{"path" => "lib/foo.ex"}, ...]}

  ### With Content Search

      args = %{
        "pattern" => "**/*.ex",
        "content" => "defmodule",
        "case_sensitive" => false
      }
      {:ok, result} = Codex.Tools.FileSearchTool.invoke(args, %{})
      # => %{"count" => 10, "files" => [%{"path" => "lib/foo.ex", "matches" => [...]}]}

  ### With Registry

      {:ok, _handle} = Codex.Tools.register(Codex.Tools.FileSearchTool,
        base_path: "/project",
        max_results: 50
      )

      {:ok, result} = Codex.Tools.invoke("file_search", %{"pattern" => "*.ex"}, %{})

  ## Result Format

  Results are returned as a map with:

    * `"count"` - Number of matching files
    * `"files"` - List of file matches, each with:
      * `"path"` - Relative path from base_path
      * `"matches"` - (optional) List of content matches with line numbers

  ## Pattern Syntax

  Uses Elixir's `Path.wildcard/2` for glob patterns:

    * `*` - Matches any characters except path separators
    * `**` - Matches any characters including path separators (recursive)
    * `?` - Matches a single character
    * `[abc]` - Matches any character in the brackets
    * `{a,b}` - Matches either pattern

  Examples:
    * `"*.ex"` - All `.ex` files in base directory
    * `"**/*.ex"` - All `.ex` files recursively
    * `"lib/**/*.{ex,exs}"` - All Elixir files under lib/
    * `"test/*_test.exs"` - All test files in test/
  """

  @behaviour Codex.Tool

  alias Codex.Config.Defaults
  alias Codex.Tools.Hosted

  @default_max_results Defaults.file_search_max_results()

  @impl true
  def metadata do
    %{
      name: "file_search",
      description: "Search for files by name pattern or content",
      schema: %{
        "type" => "object",
        "properties" => %{
          "pattern" => %{
            "type" => "string",
            "description" => "Glob pattern for file names (e.g., '**/*.ex')"
          },
          "content" => %{
            "type" => "string",
            "description" => "Fixed text to search within files (optional)"
          },
          "base_path" => %{
            "type" => "string",
            "description" => "Base directory for search (optional)"
          },
          "max_results" => %{
            "type" => "integer",
            "description" => "Maximum number of results (default: 100)"
          },
          "case_sensitive" => %{
            "type" => "boolean",
            "description" => "Case-sensitive search (default: true)"
          }
        },
        "required" => ["pattern"],
        "additionalProperties" => false
      }
    }
  end

  @impl true
  def invoke(args, context) do
    metadata = Map.get(context, :metadata, %{})

    pattern = Map.fetch!(args, "pattern")
    content = Map.get(args, "content")

    base_path =
      Map.get(args, "base_path") ||
        Hosted.metadata_value(metadata, :base_path) ||
        Map.get(context, :base_path) ||
        File.cwd!()

    max_results =
      Map.get(args, "max_results") ||
        Hosted.metadata_value(metadata, :max_results, @default_max_results)

    case_sensitive =
      case Map.get(args, "case_sensitive") do
        nil -> get_boolean_option(metadata, :case_sensitive, true)
        value -> value
      end

    include_hidden = get_boolean_option(metadata, :include_hidden, false)

    with {:ok, files} <- find_files(pattern, base_path, include_hidden),
         {:ok, matched} <- maybe_search_content(files, content, case_sensitive, base_path),
         results <- limit_results(matched, max_results) do
      {:ok, format_result(results)}
    end
  end

  defp find_files(pattern, base_path, include_hidden) do
    full_pattern = Path.join(base_path, pattern)

    files =
      full_pattern
      |> Path.wildcard(match_dot: include_hidden)
      |> Enum.filter(&File.regular?/1)
      |> Enum.map(&Path.relative_to(&1, base_path))
      |> Enum.sort()

    {:ok, files}
  rescue
    e -> {:error, {:glob_error, Exception.message(e)}}
  end

  defp maybe_search_content(files, nil, _case_sensitive, _base_path) do
    {:ok, Enum.map(files, &%{path: &1, matches: nil})}
  end

  defp maybe_search_content(files, "", _case_sensitive, _base_path) do
    {:ok, Enum.map(files, &%{path: &1, matches: nil})}
  end

  defp maybe_search_content(files, content, case_sensitive, base_path) do
    results =
      files
      |> Enum.map(fn path ->
        full_path = Path.join(base_path, path)
        matches = search_file(full_path, content, case_sensitive)
        %{path: path, matches: matches}
      end)
      |> Enum.filter(fn %{matches: m} -> m != [] end)

    {:ok, results}
  end

  defp search_file(path, content, case_sensitive) do
    case File.read(path) do
      {:ok, file_content} -> search_content(file_content, content, case_sensitive)
      {:error, _} -> []
    end
  end

  # Search content if it's valid UTF-8 text, otherwise skip binary files
  defp search_content(content, needle, case_sensitive) do
    if String.valid?(content) do
      normalized_needle = normalize_search_text(needle, case_sensitive)

      content
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _} ->
        line
        |> normalize_search_text(case_sensitive)
        |> String.contains?(normalized_needle)
      end)
      |> Enum.map(fn {line, num} -> %{line_number: num, text: String.trim(line)} end)
    else
      []
    end
  end

  defp normalize_search_text(value, true), do: value
  defp normalize_search_text(value, false), do: String.downcase(value)

  defp limit_results(results, max) do
    Enum.take(results, max)
  end

  defp format_result(results) do
    %{
      "count" => length(results),
      "files" =>
        Enum.map(results, fn r ->
          base = %{"path" => r.path}

          if r.matches do
            Map.put(
              base,
              "matches",
              Enum.map(r.matches, fn m ->
                %{"line" => m.line_number, "text" => m.text}
              end)
            )
          else
            base
          end
        end)
    }
  end

  # Helper to get boolean options that properly handles false values.
  # The Hosted.metadata_value/3 function uses || which treats false as falsy,
  # so we need to use Map.fetch/2 instead.
  defp get_boolean_option(metadata, key, default) do
    case Map.fetch(metadata, key) do
      {:ok, value} when is_boolean(value) ->
        value

      _ ->
        case Map.fetch(metadata, to_string(key)) do
          {:ok, value} when is_boolean(value) -> value
          _ -> default
        end
    end
  end
end
