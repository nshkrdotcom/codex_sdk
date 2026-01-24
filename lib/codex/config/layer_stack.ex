defmodule Codex.Config.LayerStack do
  @moduledoc false

  @type layer_source :: :system | :user | :project
  @type layer :: %{
          source: layer_source(),
          path: String.t(),
          config: map()
        }

  @default_system_config_path "/etc/codex/config.toml"
  @default_project_root_markers [".git"]

  @spec load(String.t(), String.t() | nil) :: {:ok, [layer()]} | {:error, term()}
  def load(codex_home, cwd \\ nil) when is_binary(codex_home) do
    cwd = normalize_cwd(cwd)

    with {:ok, base_layers} <- load_base_layers(codex_home) do
      case cwd do
        nil ->
          {:ok, base_layers}

        _ ->
          with {:ok, project_layers} <- load_project_layers(base_layers, cwd) do
            {:ok, base_layers ++ project_layers}
          end
      end
    end
  end

  @spec effective_config([layer()]) :: map()
  def effective_config(layers) when is_list(layers) do
    Enum.reduce(layers, %{}, fn layer, acc -> merge_configs(acc, layer.config) end)
  end

  @spec remote_models_enabled?(String.t(), String.t() | nil) :: boolean()
  def remote_models_enabled?(codex_home, cwd \\ nil) when is_binary(codex_home) do
    case load(codex_home, cwd) do
      {:ok, layers} ->
        layers
        |> effective_config()
        |> get_in(["features", "remote_models"])
        |> Kernel.===(true)

      {:error, _reason} ->
        false
    end
  end

  defp load_base_layers(codex_home) do
    with {:ok, system_layers} <- load_system_layers() do
      user_path = Path.join(codex_home, "config.toml")

      case read_required_config(user_path) do
        {:ok, config} ->
          {:ok, system_layers ++ [%{source: :user, path: user_path, config: config}]}

        {:error, _} = error ->
          error
      end
    end
  end

  defp load_system_layers do
    case read_optional_config(system_config_path()) do
      {:ok, config} -> {:ok, [%{source: :system, path: system_config_path(), config: config}]}
      :missing -> {:ok, []}
      {:error, _} = error -> error
    end
  end

  defp load_project_layers(base_layers, cwd) do
    base_config = effective_config(base_layers)

    with {:ok, markers} <- project_root_markers(base_config) do
      project_root = find_project_root(cwd, markers || @default_project_root_markers)
      load_project_layers_between(project_root, cwd)
    end
  end

  defp load_project_layers_between(project_root, cwd) do
    dirs = dirs_between(project_root, cwd)

    Enum.reduce_while(dirs, {:ok, []}, fn dir, {:ok, layers} ->
      case project_layer_for_dir(dir) do
        {:ok, nil} ->
          {:cont, {:ok, layers}}

        {:ok, layer} ->
          {:cont, {:ok, layers ++ [layer]}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
  end

  defp project_layer_for_dir(dir) do
    dot_codex = Path.join(dir, ".codex")

    if File.dir?(dot_codex) do
      config_path = Path.join(dot_codex, "config.toml")

      case read_project_config(config_path) do
        {:ok, config} -> {:ok, %{source: :project, path: config_path, config: config}}
        {:error, _} = error -> error
      end
    else
      {:ok, nil}
    end
  end

  defp project_root_markers(config) when is_map(config) do
    case Map.get(config, "project_root_markers") do
      nil ->
        {:ok, nil}

      markers when is_list(markers) ->
        if Enum.all?(markers, &is_binary/1) do
          {:ok, markers}
        else
          {:error, {:invalid_project_root_markers, markers}}
        end

      other ->
        {:error, {:invalid_project_root_markers, other}}
    end
  end

  defp read_optional_config(path) do
    case File.read(path) do
      {:ok, contents} -> parse_config(contents, path)
      {:error, :enoent} -> :missing
      {:error, reason} -> {:error, {:config_read_failed, path, reason}}
    end
  end

  defp read_required_config(path) do
    case File.read(path) do
      {:ok, contents} -> parse_config(contents, path)
      {:error, :enoent} -> {:ok, %{}}
      {:error, reason} -> {:error, {:config_read_failed, path, reason}}
    end
  end

  defp read_project_config(path) do
    case File.read(path) do
      {:ok, contents} -> parse_config(contents, path)
      {:error, :enoent} -> {:ok, %{}}
      {:error, reason} -> {:error, {:config_read_failed, path, reason}}
    end
  end

  defp parse_config(contents, path) do
    case parse_config_contents(contents) do
      {:ok, config} -> {:ok, config}
      {:error, reason} -> {:error, {:invalid_toml, path, reason}}
    end
  end

  defp parse_config_contents(contents) do
    with {:ok, config} <- parse_toml_subset(contents),
         :ok <- validate_config(config) do
      {:ok, config}
    end
  end

  defp parse_toml_subset(contents) when is_binary(contents) do
    contents
    |> String.split(~r/\r?\n/, trim: false)
    |> parse_lines(%{}, nil)
  end

  defp parse_lines([], acc, _section), do: {:ok, acc}

  defp parse_lines([line | rest], acc, section) do
    line = line |> strip_comments() |> String.trim()

    cond do
      line == "" ->
        parse_lines(rest, acc, section)

      table = parse_table(line) ->
        parse_lines(rest, acc, table)

      true ->
        case parse_key_value(line, acc, section) do
          {:ok, updated} -> parse_lines(rest, updated, section)
          {:error, _} = error -> error
        end
    end
  end

  defp parse_table(line) do
    case Regex.run(~r/^\[(.+)\]$/, line) do
      [_, name] ->
        name = String.trim(name)

        case name do
          "features" -> "features"
          "history" -> "history"
          "shell_environment_policy" -> "shell_environment_policy"
          _ -> :skip
        end

      _ ->
        nil
    end
  end

  defp parse_key_value(line, acc, section) do
    case String.split(line, "=", parts: 2) do
      [raw_key, raw_value] ->
        key = String.trim(raw_key)
        raw_value = String.trim(raw_value)

        with {:ok, value} <- parse_value(raw_value) do
          {:ok, put_config_value(acc, section, key, value)}
        end

      _ ->
        {:error, {:invalid_toml_line, line}}
    end
  end

  defp put_config_value(acc, :skip, _key, _value), do: acc

  defp put_config_value(acc, nil, "project_root_markers", value),
    do: Map.put(acc, "project_root_markers", value)

  defp put_config_value(acc, nil, "cli_auth_credentials_store", value),
    do: Map.put(acc, "cli_auth_credentials_store", value)

  defp put_config_value(acc, nil, "mcp_oauth_credentials_store", value),
    do: Map.put(acc, "mcp_oauth_credentials_store", value)

  defp put_config_value(acc, nil, "forced_login_method", value),
    do: Map.put(acc, "forced_login_method", value)

  defp put_config_value(acc, nil, "forced_chatgpt_workspace_id", value),
    do: Map.put(acc, "forced_chatgpt_workspace_id", value)

  defp put_config_value(acc, nil, "model", value),
    do: Map.put(acc, "model", value)

  defp put_config_value(acc, nil, "model_reasoning_effort", value),
    do: Map.put(acc, "model_reasoning_effort", value)

  defp put_config_value(acc, nil, "model_provider", value),
    do: Map.put(acc, "model_provider", value)

  defp put_config_value(acc, nil, "features", value) when is_map(value),
    do: Map.put(acc, "features", value)

  defp put_config_value(acc, nil, "features", _value), do: acc

  defp put_config_value(acc, nil, "history", value) when is_map(value),
    do: Map.put(acc, "history", value)

  defp put_config_value(acc, nil, "history", _value), do: acc

  defp put_config_value(acc, nil, "shell_environment_policy", value) when is_map(value),
    do: Map.put(acc, "shell_environment_policy", value)

  defp put_config_value(acc, nil, "shell_environment_policy", _value), do: acc

  defp put_config_value(acc, nil, key, value), do: maybe_put_dotted_value(acc, key, value)

  defp put_config_value(acc, "features", key, value) do
    Map.update(acc, "features", %{key => value}, &Map.put(&1, key, value))
  end

  defp put_config_value(acc, "history", key, value) do
    Map.update(acc, "history", %{key => value}, &Map.put(&1, key, value))
  end

  defp put_config_value(acc, "shell_environment_policy", key, value) do
    Map.update(acc, "shell_environment_policy", %{key => value}, &Map.put(&1, key, value))
  end

  defp maybe_put_dotted_value(acc, key, value) do
    case String.split(key, ".") do
      ["features" | rest] when rest != [] ->
        put_nested_path(acc, ["features" | rest], value)

      ["history" | rest] when rest != [] ->
        put_nested_path(acc, ["history" | rest], value)

      ["shell_environment_policy" | rest] when rest != [] ->
        put_nested_path(acc, ["shell_environment_policy" | rest], value)

      _ ->
        acc
    end
  end

  defp put_nested_path(acc, [root | rest], value) do
    Map.update(acc, root, build_nested(rest, value), fn existing ->
      merge_nested(existing, rest, value)
    end)
  end

  defp build_nested([], value), do: value
  defp build_nested([key | rest], value), do: %{key => build_nested(rest, value)}

  defp merge_nested(_existing, [], value), do: value

  defp merge_nested(%{} = existing, [key | rest], value) do
    Map.update(existing, key, build_nested(rest, value), fn nested ->
      merge_nested(nested, rest, value)
    end)
  end

  defp merge_nested(_existing, rest, value), do: build_nested(rest, value)

  defp strip_comments(line) do
    line
    |> String.to_charlist()
    |> strip_comments([], nil)
    |> Enum.reverse()
    |> to_string()
  end

  defp strip_comments([], acc, _quote), do: acc

  defp strip_comments([?# | _rest], acc, nil), do: acc

  defp strip_comments([char | rest], acc, quote) do
    strip_comments(rest, [char | acc], next_quote(char, quote))
  end

  defp next_quote(char, nil) when char in [?", ?'], do: char
  defp next_quote(char, quote) when char == quote, do: nil
  defp next_quote(_char, quote), do: quote

  defp parse_value(value) do
    value = String.trim(value)

    cond do
      value == "" ->
        {:error, {:invalid_toml_value, value}}

      boolean_string?(value) ->
        {:ok, value == "true"}

      array_string?(value) ->
        parse_array(value)

      inline_table_string?(value) ->
        parse_inline_table(value)

      quoted_string?(value) ->
        {:ok, strip_quotes(value)}

      integer_string?(value) ->
        {:ok, parse_integer(value)}

      true ->
        {:ok, value}
    end
  end

  defp boolean_string?("true"), do: true
  defp boolean_string?("false"), do: true
  defp boolean_string?(_), do: false

  defp array_string?(value) do
    String.starts_with?(value, "[") and String.ends_with?(value, "]")
  end

  defp inline_table_string?(value) do
    String.starts_with?(value, "{") and String.ends_with?(value, "}")
  end

  defp quoted_string?(value) do
    (String.starts_with?(value, "\"") and String.ends_with?(value, "\"")) or
      (String.starts_with?(value, "'") and String.ends_with?(value, "'"))
  end

  defp strip_quotes(value) do
    value
    |> String.trim_leading("\"")
    |> String.trim_trailing("\"")
    |> String.trim_leading("'")
    |> String.trim_trailing("'")
  end

  defp integer_string?(value) do
    String.match?(value, ~r/^-?\d+(_\d+)*$/)
  end

  defp parse_integer(value) do
    value
    |> String.replace("_", "")
    |> String.to_integer()
  end

  defp parse_array(value) do
    value
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
    |> String.trim()
    |> parse_array_inner()
  end

  defp parse_array_inner(""), do: {:ok, []}

  defp parse_array_inner(inner) do
    inner
    |> String.split(",", trim: true)
    |> Enum.reduce_while({:ok, []}, fn entry, {:ok, acc} ->
      case parse_value(entry) do
        {:ok, parsed} -> {:cont, {:ok, acc ++ [parsed]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp parse_inline_table(value) do
    value
    |> String.trim_leading("{")
    |> String.trim_trailing("}")
    |> String.trim()
    |> parse_inline_table_inner()
  end

  defp parse_inline_table_inner(""), do: {:ok, %{}}

  defp parse_inline_table_inner(inner) do
    inner
    |> String.split(",", trim: true)
    |> Enum.reduce_while({:ok, %{}}, fn entry, {:ok, acc} ->
      case parse_inline_entry(entry) do
        {:ok, {key, parsed}} -> {:cont, {:ok, Map.put(acc, key, parsed)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp parse_inline_entry(entry) do
    case String.split(entry, "=", parts: 2) do
      [raw_key, raw_value] ->
        key = String.trim(raw_key)
        raw_value = String.trim(raw_value)

        case parse_value(raw_value) do
          {:ok, parsed} -> {:ok, {key, parsed}}
          {:error, _} = error -> error
        end

      _ ->
        {:error, {:invalid_toml_inline_table, entry}}
    end
  end

  defp validate_config(%{} = config) do
    with :ok <- validate_features(config),
         :ok <- validate_model_provider(config),
         :ok <- validate_history(config),
         :ok <- validate_shell_environment_policy(config),
         :ok <- validate_project_root_markers(config),
         :ok <- validate_cli_auth_store(config),
         :ok <- validate_mcp_oauth_store(config) do
      validate_forced_login_config(config)
    end
  end

  defp validate_config(_), do: {:error, :invalid_config_root}

  defp validate_features(config) do
    case fetch_value(config, ["features", :features]) do
      nil ->
        :ok

      %{} = features ->
        validate_boolean_map(features, :invalid_features)

      other ->
        {:error, {:invalid_features, other}}
    end
  end

  defp validate_model_provider(config) do
    case fetch_value(config, ["model_provider", :model_provider]) do
      nil ->
        :ok

      value when is_binary(value) ->
        :ok

      other ->
        {:error, {:invalid_model_provider, other}}
    end
  end

  defp validate_history(config) do
    case fetch_value(config, ["history", :history]) do
      nil ->
        :ok

      %{} = history ->
        with :ok <- validate_history_persistence(history) do
          validate_history_max_bytes(history)
        end

      other ->
        {:error, {:invalid_history, other}}
    end
  end

  defp validate_history_persistence(history) do
    case fetch_value(history, ["persistence", :persistence]) do
      nil -> :ok
      value when is_binary(value) -> :ok
      other -> {:error, {:invalid_history_persistence, other}}
    end
  end

  defp validate_history_max_bytes(history) do
    case fetch_value(history, ["max_bytes", "maxBytes", :max_bytes, :maxBytes]) do
      nil ->
        :ok

      value when is_integer(value) and value >= 0 ->
        :ok

      other ->
        {:error, {:invalid_history_max_bytes, other}}
    end
  end

  defp validate_shell_environment_policy(config) do
    case fetch_value(config, ["shell_environment_policy", :shell_environment_policy]) do
      nil ->
        :ok

      %{} = policy ->
        with :ok <- validate_shell_env_inherit(policy),
             :ok <- validate_shell_env_ignore_default_excludes(policy),
             :ok <- validate_shell_env_list(policy, "exclude", :exclude),
             :ok <- validate_shell_env_list(policy, "include_only", :include_only) do
          validate_shell_env_set(policy)
        end

      other ->
        {:error, {:invalid_shell_environment_policy, other}}
    end
  end

  defp validate_shell_env_inherit(policy) do
    case fetch_value(policy, ["inherit", :inherit]) do
      nil -> :ok
      value when is_binary(value) -> :ok
      other -> {:error, {:invalid_shell_environment_inherit, other}}
    end
  end

  defp validate_shell_env_ignore_default_excludes(policy) do
    case fetch_value(policy, ["ignore_default_excludes", :ignore_default_excludes]) do
      nil -> :ok
      value when is_boolean(value) -> :ok
      other -> {:error, {:invalid_shell_environment_ignore_default_excludes, other}}
    end
  end

  defp validate_shell_env_list(policy, key, atom_key) do
    case fetch_value(policy, [key, atom_key]) do
      nil ->
        :ok

      value when is_list(value) ->
        if Enum.all?(value, &is_binary/1) do
          :ok
        else
          {:error, {:invalid_shell_environment_list, key, value}}
        end

      other ->
        {:error, {:invalid_shell_environment_list, key, other}}
    end
  end

  defp validate_shell_env_set(policy) do
    case fetch_value(policy, ["set", :set]) do
      nil ->
        :ok

      %{} = set ->
        validate_string_map(set, :invalid_shell_environment_set)

      other ->
        {:error, {:invalid_shell_environment_set, other}}
    end
  end

  defp validate_boolean_map(map, error_tag) do
    if Enum.all?(map, fn {_key, value} -> is_boolean(value) end) do
      :ok
    else
      {:error, {error_tag, map}}
    end
  end

  defp validate_string_map(map, error_tag) do
    if Enum.all?(map, fn {key, value} -> is_binary(key) and is_binary(value) end) do
      :ok
    else
      {:error, {error_tag, map}}
    end
  end

  defp validate_project_root_markers(config) do
    case fetch_value(config, ["project_root_markers", :project_root_markers]) do
      nil ->
        :ok

      value when is_list(value) ->
        if Enum.all?(value, &is_binary/1) do
          :ok
        else
          {:error, {:invalid_project_root_markers, value}}
        end

      other ->
        {:error, {:invalid_project_root_markers, other}}
    end
  end

  defp validate_cli_auth_store(config) do
    case fetch_value(config, ["cli_auth_credentials_store", :cli_auth_credentials_store]) do
      nil ->
        :ok

      value when is_binary(value) ->
        if value in ["file", "keyring", "auto"] do
          :ok
        else
          {:error, {:invalid_cli_auth_credentials_store, value}}
        end

      other ->
        {:error, {:invalid_cli_auth_credentials_store, other}}
    end
  end

  defp validate_mcp_oauth_store(config) do
    case fetch_value(config, ["mcp_oauth_credentials_store", :mcp_oauth_credentials_store]) do
      nil ->
        :ok

      value when is_binary(value) ->
        if value in ["file", "keyring", "auto"] do
          :ok
        else
          {:error, {:invalid_mcp_oauth_credentials_store, value}}
        end

      other ->
        {:error, {:invalid_mcp_oauth_credentials_store, other}}
    end
  end

  defp validate_forced_login_config(config) do
    with :ok <- validate_forced_login_method(config) do
      validate_forced_chatgpt_workspace_id(config)
    end
  end

  defp validate_forced_login_method(config) do
    case fetch_value(config, ["forced_login_method", :forced_login_method]) do
      nil ->
        :ok

      value when is_binary(value) ->
        if value in ["chatgpt", "api"] do
          :ok
        else
          {:error, {:invalid_forced_login_method, value}}
        end

      other ->
        {:error, {:invalid_forced_login_method, other}}
    end
  end

  defp validate_forced_chatgpt_workspace_id(config) do
    case fetch_value(config, ["forced_chatgpt_workspace_id", :forced_chatgpt_workspace_id]) do
      nil -> :ok
      value when is_binary(value) -> :ok
      other -> {:error, {:invalid_forced_chatgpt_workspace_id, other}}
    end
  end

  defp fetch_value(map, [key | rest]) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> fetch_value(map, rest)
    end
  end

  defp fetch_value(_map, []), do: nil

  defp merge_configs(base, override) when is_map(base) and is_map(override) do
    Map.merge(base, override, fn _key, left, right ->
      if is_map(left) and is_map(right) do
        merge_configs(left, right)
      else
        right
      end
    end)
  end

  defp dirs_between(project_root, cwd) do
    project_root = Path.expand(project_root)
    cwd = Path.expand(cwd)

    dirs =
      cwd
      |> ancestors()
      |> Enum.reduce_while([], fn dir, acc ->
        acc = [dir | acc]

        if dir == project_root do
          {:halt, acc}
        else
          {:cont, acc}
        end
      end)

    dirs
    |> Enum.reverse()
    |> case do
      [] -> [cwd]
      list -> list
    end
  end

  defp ancestors(path) do
    path = Path.expand(path)

    Stream.unfold(path, fn
      nil ->
        nil

      current ->
        parent = Path.dirname(current)
        next = if parent == current, do: nil, else: parent
        {current, next}
    end)
  end

  defp find_project_root(cwd, []), do: Path.expand(cwd)

  defp find_project_root(cwd, markers) when is_list(markers) do
    Enum.find(ancestors(cwd), Path.expand(cwd), &has_marker?(&1, markers))
  end

  defp has_marker?(dir, markers) do
    Enum.any?(markers, fn marker ->
      File.exists?(Path.join(dir, marker))
    end)
  end

  defp normalize_cwd(nil) do
    case File.cwd() do
      {:ok, cwd} -> cwd
      _ -> nil
    end
  end

  defp normalize_cwd(cwd) when is_binary(cwd), do: cwd
  defp normalize_cwd(_), do: nil

  defp system_config_path do
    case Application.get_env(:codex_sdk, :system_config_path) do
      nil -> @default_system_config_path
      value -> value
    end
  end
end
