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
    lines = String.split(contents, ~r/\R/)

    initial = %{
      section: nil,
      remote_models: nil,
      project_root_markers: nil,
      markers_buffer: nil
    }

    with {:ok, state} <- parse_config_lines(lines, initial) do
      build_config(state)
    end
  end

  defp parse_config_lines(lines, state) do
    Enum.reduce_while(lines, {:ok, state}, fn line, {:ok, acc} ->
      case parse_config_line(line, acc) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp parse_config_line(line, %{markers_buffer: buffer} = state) when is_list(buffer) do
    stripped = strip_comment(line)
    buffer = buffer ++ [stripped]

    if String.contains?(stripped, "]") do
      raw = Enum.join(buffer, "")

      case parse_marker_list(raw) do
        {:ok, markers} ->
          {:ok, %{state | project_root_markers: markers, markers_buffer: nil}}

        {:error, _} = error ->
          error
      end
    else
      {:ok, %{state | markers_buffer: buffer}}
    end
  end

  defp parse_config_line(line, state) do
    stripped = strip_comment(line)

    cond do
      stripped == "" ->
        {:ok, state}

      section_header?(stripped) ->
        {:ok, %{state | section: parse_section_header(stripped)}}

      state.section in [nil, ""] and key_matches?(stripped, "project_root_markers") ->
        parse_project_root_markers(stripped, state)

      state.section == "features" and key_matches?(stripped, "remote_models") ->
        parse_remote_models(stripped, state)

      true ->
        {:ok, state}
    end
  end

  defp parse_project_root_markers(line, state) do
    case split_kv(line) do
      {:ok, _key, value} ->
        case parse_marker_list(value) do
          {:ok, markers} -> {:ok, %{state | project_root_markers: markers}}
          {:error, :incomplete} -> {:ok, %{state | markers_buffer: [value]}}
          {:error, _} = error -> error
        end

      {:error, _} = error ->
        error
    end
  end

  defp parse_remote_models(line, state) do
    case split_kv(line) do
      {:ok, _key, value} ->
        case parse_bool(value) do
          bool when is_boolean(bool) -> {:ok, %{state | remote_models: bool}}
          _ -> {:error, {:invalid_remote_models, value}}
        end

      {:error, _} = error ->
        error
    end
  end

  defp build_config(%{remote_models: remote_models, project_root_markers: markers}) do
    config =
      %{}
      |> maybe_put("features", remote_models)
      |> maybe_put("project_root_markers", markers)

    {:ok, config}
  end

  defp maybe_put(config, _key, nil), do: config

  defp maybe_put(config, "features", value) when is_boolean(value) do
    Map.put(config, "features", %{"remote_models" => value})
  end

  defp maybe_put(config, "project_root_markers", value) when is_list(value) do
    Map.put(config, "project_root_markers", value)
  end

  defp maybe_put(config, _key, _value), do: config

  defp parse_marker_list(value) do
    trimmed = String.trim(value)

    cond do
      !String.contains?(trimmed, "[") ->
        {:error, {:invalid_project_root_markers, value}}

      String.contains?(trimmed, "]") ->
        do_parse_marker_list(trimmed)

      true ->
        {:error, :incomplete}
    end
  end

  defp do_parse_marker_list(value) do
    case Regex.run(~r/\[(.*)\]/s, value) do
      [_, inner] ->
        inner
        |> String.trim()
        |> markers_from_inner(value)

      _ ->
        {:error, {:invalid_project_root_markers, value}}
    end
  end

  defp markers_from_inner("", _value), do: {:ok, []}

  defp markers_from_inner(inner, value) do
    case extract_markers(inner) do
      [] -> {:error, {:invalid_project_root_markers, value}}
      markers -> {:ok, markers}
    end
  end

  defp extract_markers(inner) do
    Regex.scan(~r/"([^"]*)"/, inner)
    |> Enum.map(fn [_full, match] -> match end)
  end

  defp split_kv(line) do
    case String.split(line, "=", parts: 2) do
      [key, value] ->
        {:ok, String.trim(key), String.trim(value)}

      _ ->
        {:error, {:invalid_config_line, line}}
    end
  end

  defp key_matches?(line, key) do
    case split_kv(line) do
      {:ok, ^key, _value} -> true
      _ -> false
    end
  end

  defp section_header?(line) do
    String.starts_with?(line, "[") && String.ends_with?(line, "]")
  end

  defp parse_section_header(line) do
    line
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
    |> String.trim()
  end

  defp strip_comment(line) do
    line
    |> String.split("#", parts: 2)
    |> List.first()
    |> String.split(";", parts: 2)
    |> List.first()
    |> String.trim()
  end

  defp parse_bool(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "true" -> true
      "false" -> false
      _ -> nil
    end
  end

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
