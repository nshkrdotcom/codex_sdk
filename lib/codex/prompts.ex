defmodule Codex.Prompts do
  @moduledoc """
  Custom prompt discovery and expansion helpers.
  """

  alias Codex.Auth

  @type prompt :: %{
          name: String.t(),
          path: String.t(),
          content: String.t(),
          description: String.t() | nil,
          argument_hint: String.t() | nil
        }

  @prompt_arg_regex ~r/(?<!\$)\$[A-Z][A-Z0-9_]*/

  @doc """
  Lists custom prompts from `$CODEX_HOME/prompts` (or a provided directory).

  ## Options

    * `:dir` - override prompt directory
    * `:exclude` - list of prompt names to skip
  """
  @spec list(keyword()) :: {:ok, [prompt()]}
  def list(opts \\ []) do
    dir = Keyword.get(opts, :dir) || Path.join(Auth.codex_home(), "prompts")
    exclude = opts |> Keyword.get(:exclude, []) |> Enum.map(&to_string/1) |> MapSet.new()

    list_from_dir(dir, exclude)
  end

  @doc """
  Expands a prompt's content using positional or named arguments.

  If the prompt contains named placeholders (e.g. `$USER`), the args must be
  provided as `KEY=value` pairs. Otherwise positional arguments expand `$1..$9`
  and `$ARGUMENTS`.
  """
  @spec expand(prompt() | map() | String.t(), String.t() | [String.t()] | map() | nil) ::
          {:ok, String.t()} | {:error, map()}
  def expand(prompt, args \\ nil) do
    {name, content} = normalize_prompt(prompt)
    command = "/prompts:" <> name
    required = prompt_argument_names(content)

    if required == [] do
      positional = parse_positional_args(args)
      {:ok, expand_numeric_placeholders(content, positional)}
    else
      with {:ok, inputs} <- parse_named_args(args),
           :ok <- ensure_required(required, inputs) do
        {:ok, replace_named_placeholders(content, inputs)}
      else
        {:error, {:missing_args, missing}} ->
          {:error,
           %{
             type: :missing_args,
             missing: missing,
             message: missing_args_message(command, missing)
           }}

        {:error, {:invalid_args, reason}} ->
          {:error, %{type: :invalid_args, message: invalid_args_message(command, reason)}}
      end
    end
  end

  defp normalize_prompt(%{content: content} = prompt) when is_binary(content) do
    name = Map.get(prompt, :name) || Map.get(prompt, "name") || "prompt"
    {to_string(name), content}
  end

  defp normalize_prompt(%{"content" => content} = prompt) when is_binary(content) do
    name = Map.get(prompt, "name") || Map.get(prompt, :name) || "prompt"
    {to_string(name), content}
  end

  defp normalize_prompt(content) when is_binary(content), do: {"prompt", content}

  defp normalize_prompt(other), do: {"prompt", to_string(other)}

  defp list_from_dir(dir, exclude) do
    case File.ls(dir) do
      {:ok, entries} -> {:ok, build_prompts(entries, dir, exclude)}
      {:error, _} -> {:ok, []}
    end
  end

  defp build_prompts(entries, dir, exclude) do
    entries
    |> Enum.flat_map(fn entry ->
      case load_prompt_file(dir, entry, exclude) do
        {:ok, prompt} -> [prompt]
        :skip -> []
      end
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp load_prompt_file(dir, entry, exclude) do
    path = Path.join(dir, entry)

    with true <- prompt_file?(path),
         name <- path |> Path.basename() |> Path.rootname(),
         false <- MapSet.member?(exclude, name),
         {:ok, contents} <- File.read(path),
         true <- String.valid?(contents) do
      {description, argument_hint, body} = parse_frontmatter(contents)

      {:ok,
       %{
         name: name,
         path: path,
         content: body,
         description: description,
         argument_hint: argument_hint
       }}
    else
      _ -> :skip
    end
  end

  defp prompt_file?(path) do
    File.regular?(path) and String.downcase(Path.extname(path)) == ".md"
  end

  defp parse_frontmatter(content) do
    case String.split(content, "\n", trim: false) do
      ["---" | rest] -> parse_frontmatter_lines(rest, content)
      _ -> {nil, nil, content}
    end
  end

  defp parse_frontmatter_lines(lines, fallback) do
    {meta_lines, body_lines, closed?} = split_frontmatter(lines, [])

    if closed? do
      {description, argument_hint} = parse_meta(meta_lines)
      {description, argument_hint, Enum.join(body_lines, "\n")}
    else
      {nil, nil, fallback}
    end
  end

  defp split_frontmatter([], acc), do: {Enum.reverse(acc), [], false}

  defp split_frontmatter([line | rest], acc) do
    if String.trim(line) == "---" do
      {Enum.reverse(acc), rest, true}
    else
      split_frontmatter(rest, [line | acc])
    end
  end

  defp parse_meta(lines) do
    Enum.reduce(lines, {nil, nil}, &parse_meta_line/2)
  end

  defp parse_meta_line(line, {desc, hint}) do
    trimmed = String.trim(line)

    cond do
      trimmed == "" -> {desc, hint}
      String.starts_with?(trimmed, "#") -> {desc, hint}
      true -> parse_meta_entry(trimmed, desc, hint)
    end
  end

  defp parse_meta_entry(trimmed, desc, hint) do
    case String.split(trimmed, ":", parts: 2) do
      [raw_key, raw_value] ->
        key = String.downcase(String.trim(raw_key))
        value = raw_value |> String.trim() |> strip_wrapping_quotes()

        case key do
          "description" -> {value, hint}
          "argument-hint" -> {desc, value}
          "argument_hint" -> {desc, value}
          _ -> {desc, hint}
        end

      _ ->
        {desc, hint}
    end
  end

  defp strip_wrapping_quotes(value) do
    if String.length(value) >= 2 do
      first = String.first(value)
      last = String.last(value)

      if (first == "\"" and last == "\"") or (first == "'" and last == "'") do
        value |> String.slice(1, String.length(value) - 2)
      else
        value
      end
    else
      value
    end
  end

  defp prompt_argument_names(content) do
    @prompt_arg_regex
    |> Regex.scan(content)
    |> Enum.map(&List.first/1)
    |> Enum.map(&String.trim_leading(&1, "$"))
    |> Enum.reject(&(&1 == "ARGUMENTS"))
    |> Enum.reduce({MapSet.new(), []}, fn name, {seen, acc} ->
      if MapSet.member?(seen, name) do
        {seen, acc}
      else
        {MapSet.put(seen, name), acc ++ [name]}
      end
    end)
    |> elem(1)
  end

  defp parse_named_args(nil), do: {:ok, %{}}

  defp parse_named_args(%{} = args), do: {:ok, stringify_keys(args)}

  defp parse_named_args(args) when is_list(args) do
    if Keyword.keyword?(args) do
      {:ok, stringify_keys(Map.new(args))}
    else
      parse_named_tokens(args)
    end
  end

  defp parse_named_args(args) when is_binary(args) do
    with {:ok, tokens} <- split_tokens(args) do
      parse_named_tokens(tokens)
    end
  end

  defp parse_named_args(_), do: {:ok, %{}}

  defp parse_named_tokens(tokens) do
    Enum.reduce_while(tokens, {:ok, %{}}, fn token, {:ok, acc} ->
      case parse_named_token(token) do
        {:ok, {key, value}} -> {:cont, {:ok, Map.put(acc, key, value)}}
        {:error, reason} -> {:halt, {:error, {:invalid_args, reason}}}
      end
    end)
  end

  defp parse_named_token(token) do
    token = to_string(token)

    case String.split(token, "=", parts: 2) do
      [key, value] when key != "" -> {:ok, {key, value}}
      [_, _] -> {:error, {:missing_key, token}}
      _ -> {:error, {:missing_assignment, token}}
    end
  end

  defp ensure_required(required, inputs) do
    missing = Enum.filter(required, fn key -> not Map.has_key?(inputs, key) end)

    if missing == [] do
      :ok
    else
      {:error, {:missing_args, missing}}
    end
  end

  defp parse_positional_args(nil), do: []

  defp parse_positional_args(args) when is_binary(args) do
    case split_tokens(args) do
      {:ok, tokens} -> tokens
      {:error, _} -> []
    end
  end

  defp parse_positional_args(args) when is_list(args) do
    if Keyword.keyword?(args) do
      Enum.map(args, fn {_key, value} -> to_string(value) end)
    else
      Enum.map(args, &to_string/1)
    end
  end

  defp parse_positional_args(%{} = args) do
    args
    |> Map.values()
    |> Enum.map(&to_string/1)
  end

  defp parse_positional_args(_), do: []

  defp split_tokens(args) do
    {:ok, OptionParser.split(args)}
  rescue
    error in OptionParser.ParseError ->
      {:error, {:invalid_args, {:invalid_syntax, Exception.message(error)}}}
  end

  defp replace_named_placeholders(content, inputs) do
    Regex.replace(@prompt_arg_regex, content, fn match ->
      key = String.trim_leading(match, "$")
      Map.get(inputs, key, match)
    end)
  end

  defp expand_numeric_placeholders(content, args) do
    joined_args = if args == [], do: nil, else: Enum.join(args, " ")
    do_expand_numeric(content, args, joined_args, [])
  end

  defp do_expand_numeric(<<>>, _args, _joined_args, acc) do
    acc |> Enum.reverse() |> IO.iodata_to_binary()
  end

  defp do_expand_numeric(<<"$", rest::binary>>, args, joined_args, acc) do
    case rest do
      <<"$", tail::binary>> ->
        do_expand_numeric(tail, args, joined_args, ["$$" | acc])

      <<digit, tail::binary>> when digit in ?1..?9 ->
        idx = digit - ?1
        value = Enum.at(args, idx, "")
        do_expand_numeric(tail, args, joined_args, [value | acc])

      <<"ARGUMENTS", tail::binary>> ->
        value = joined_args || ""
        do_expand_numeric(tail, args, joined_args, [value | acc])

      _ ->
        do_expand_numeric(rest, args, joined_args, ["$" | acc])
    end
  end

  defp do_expand_numeric(<<char, rest::binary>>, args, joined_args, acc) do
    do_expand_numeric(rest, args, joined_args, [<<char>> | acc])
  end

  defp missing_args_message(command, missing) do
    list = Enum.join(missing, ", ")

    "Missing required args for #{command}: #{list}. Provide as key=value (quote values with spaces)."
  end

  defp invalid_args_message(command, {:missing_assignment, token}) do
    "Could not parse #{command}: expected key=value but found '#{token}'. Wrap values in double quotes if they contain spaces."
  end

  defp invalid_args_message(command, {:missing_key, token}) do
    "Could not parse #{command}: expected a name before '=' in '#{token}'."
  end

  defp invalid_args_message(_command, {:invalid_syntax, message}), do: message

  defp invalid_args_message(command, other),
    do: "Could not parse #{command}: #{inspect(other)}"

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, val} -> {to_string(key), stringify_keys(val)} end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(other), do: other
end
