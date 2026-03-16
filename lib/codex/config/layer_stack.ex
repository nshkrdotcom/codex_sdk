defmodule Codex.Config.LayerStack do
  @moduledoc false

  @type layer_source :: :system | :user | :project
  @type layer :: %{
          source: layer_source(),
          path: String.t(),
          config: map(),
          enabled: boolean()
        }

  alias Codex.Config.Defaults

  @default_system_config_path Defaults.system_config_path()
  @default_project_root_markers Defaults.project_root_markers()
  @reserved_model_provider_ids ~w(openai ollama lmstudio)

  @spec load(String.t(), String.t() | nil) :: {:ok, [layer()]} | {:error, term()}
  def load(codex_home, cwd \\ nil) when is_binary(codex_home) do
    cwd = normalize_cwd(cwd)

    with {:ok, base_layers} <- load_base_layers(codex_home),
         {:ok, project_layers} <- maybe_load_project_layers(base_layers, cwd) do
      {:ok, base_layers ++ project_layers}
    end
  end

  defp maybe_load_project_layers(_base_layers, nil), do: {:ok, []}
  defp maybe_load_project_layers(base_layers, cwd), do: load_project_layers(base_layers, cwd)

  @spec effective_config([layer()]) :: map()
  def effective_config(layers) when is_list(layers) do
    Enum.reduce(layers, %{}, fn layer, acc ->
      if Map.get(layer, :enabled, true) do
        merge_configs(acc, layer.config)
      else
        acc
      end
    end)
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
          {:ok,
           system_layers ++ [%{source: :user, path: user_path, config: config, enabled: true}]}

        {:error, _} = error ->
          error
      end
    end
  end

  defp load_system_layers do
    requirements = read_optional_requirements(system_requirements_path())

    case read_optional_config(system_config_path()) do
      {:ok, config} ->
        {:ok,
         [
           %{
             source: :system,
             path: system_config_path(),
             config: merge_requirements(config, requirements),
             enabled: true
           }
         ]}

      :missing ->
        case requirements do
          {:ok, config} ->
            {:ok,
             [
               %{
                 source: :system,
                 path: system_requirements_path(),
                 config: %{"requirements" => config},
                 enabled: true
               }
             ]}

          :missing ->
            {:ok, []}

          {:error, _} = error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  defp load_project_layers(base_layers, cwd) do
    base_config = effective_config(base_layers)

    with {:ok, markers} <- project_root_markers(base_config) do
      project_root = find_project_root(cwd, markers || @default_project_root_markers)
      trusted = project_layers_trusted?(base_config, cwd, project_root)

      with {:ok, cwd_layer} <- cwd_layer_for_dir(cwd, trusted),
           {:ok, project_layers} <- load_project_layers_between(project_root, cwd, trusted) do
        {:ok, Enum.reject([cwd_layer | project_layers], &is_nil/1)}
      end
    end
  end

  defp load_project_layers_between(project_root, cwd, enabled) do
    dirs = dirs_between(project_root, cwd)

    Enum.reduce_while(dirs, {:ok, []}, fn dir, {:ok, layers} ->
      case project_layer_for_dir(dir, enabled) do
        {:ok, nil} ->
          {:cont, {:ok, layers}}

        {:ok, layer} ->
          {:cont, {:ok, layers ++ [layer]}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
  end

  defp cwd_layer_for_dir(dir, enabled) do
    config_path = Path.join(dir, "config.toml")

    case read_project_config(config_path) do
      {:ok, config} when map_size(config) == 0 ->
        {:ok, nil}

      {:ok, config} ->
        {:ok, %{source: :project, path: config_path, config: config, enabled: enabled}}

      {:error, _} = error ->
        error
    end
  end

  defp project_layer_for_dir(dir, enabled) do
    dot_codex = Path.join(dir, ".codex")

    if File.dir?(dot_codex) do
      config_path = Path.join(dot_codex, "config.toml")

      case read_project_config(config_path) do
        {:ok, config} when map_size(config) == 0 ->
          {:ok, nil}

        {:ok, config} ->
          {:ok, %{source: :project, path: config_path, config: config, enabled: enabled}}

        {:error, _} = error ->
          error
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

  defp read_optional_requirements(path) do
    case File.read(path) do
      {:ok, contents} -> parse_config(contents, path)
      {:error, :enoent} -> :missing
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
    with {:ok, config} <- decode_toml(contents),
         :ok <- validate_config(config) do
      {:ok, config}
    end
  end

  defp decode_toml(contents) when is_binary(contents) do
    # The toml library's runtime API and docs use `:strings`, but the published
    # typespec incorrectly advertises `:string`. Keep the runtime-correct option
    # here and isolate the bad spec at this boundary.
    case Toml.decode(contents, keys: toml_keys_opt()) do
      {:ok, config} -> {:ok, config}
      {:error, reason} -> {:error, reason}
    end
  end

  defp toml_keys_opt do
    String.to_existing_atom("strings")
  end

  defp validate_config(%{} = config) do
    with :ok <- validate_features(config),
         :ok <- validate_model_provider(config),
         :ok <- validate_openai_base_url(config),
         :ok <- validate_model_providers(config),
         :ok <- validate_history(config),
         :ok <- validate_shell_environment_policy(config),
         :ok <- validate_project_root_markers(config),
         :ok <- validate_cli_auth_store(config),
         :ok <- validate_mcp_oauth_store(config) do
      validate_forced_login_config(config)
    end
  end

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

  defp validate_openai_base_url(config) do
    case fetch_value(config, ["openai_base_url", :openai_base_url]) do
      nil ->
        :ok

      value when is_binary(value) ->
        :ok

      other ->
        {:error, {:invalid_openai_base_url, other}}
    end
  end

  defp validate_model_providers(config) do
    case fetch_value(config, ["model_providers", :model_providers]) do
      nil ->
        :ok

      %{} = providers ->
        with :ok <- validate_model_provider_entries(providers) do
          validate_reserved_model_provider_ids(providers)
        end

      other ->
        {:error, {:invalid_model_providers, other}}
    end
  end

  defp validate_model_provider_entries(providers) when is_map(providers) do
    if Enum.all?(providers, fn {key, value} -> is_binary(key) and is_map(value) end) do
      :ok
    else
      {:error, {:invalid_model_providers, providers}}
    end
  end

  defp validate_reserved_model_provider_ids(providers) when is_map(providers) do
    conflicts =
      providers
      |> Map.keys()
      |> Enum.filter(&(&1 in @reserved_model_provider_ids))
      |> Enum.sort()

    if conflicts == [] do
      :ok
    else
      {:error, {:reserved_model_provider_ids, conflicts}}
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

  defp merge_requirements(config, {:ok, requirements})
       when is_map(config) and is_map(requirements) do
    Map.put(config, "requirements", requirements)
  end

  defp merge_requirements(config, _requirements), do: config

  defp project_layers_trusted?(config, cwd, project_root) do
    projects = fetch_value(config, ["projects", :projects]) || %{}

    trust =
      project_trust_level(projects, cwd) ||
        project_trust_level(projects, project_root) ||
        (resolve_repo_root(cwd) && project_trust_level(projects, resolve_repo_root(cwd)))

    trust in ["trusted", :trusted]
  end

  defp project_trust_level(projects, path) when is_map(projects) and is_binary(path) do
    case Map.get(projects, Path.expand(path)) || Map.get(projects, path) do
      %{} = project ->
        Map.get(project, "trust_level") || Map.get(project, :trust_level)

      _ ->
        nil
    end
  end

  defp project_trust_level(_projects, _path), do: nil

  defp resolve_repo_root(cwd) when is_binary(cwd) do
    case System.cmd("git", ["-C", cwd, "rev-parse", "--show-toplevel"], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.trim()
        |> case do
          "" -> nil
          path -> path
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp system_config_path do
    case Application.get_env(:codex_sdk, :system_config_path) do
      nil -> @default_system_config_path
      value -> value
    end
  end

  defp system_requirements_path do
    system_config_path()
    |> Path.dirname()
    |> Path.join("requirements.toml")
  end
end
