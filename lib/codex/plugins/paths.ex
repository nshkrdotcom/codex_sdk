defmodule Codex.Plugins.Paths do
  @moduledoc """
  Canonical local authoring paths for plugin manifests and marketplaces.
  """

  alias Codex.Plugins.Errors

  @marketplace_relative_path Path.join([".agents", "plugins", "marketplace.json"])
  @manifest_relative_path Path.join([".codex-plugin", "plugin.json"])

  @type scope :: :repo | :personal

  @doc """
  Resolves the root directory for a repo or personal plugin scope.
  """
  @spec scope_root(scope(), keyword()) :: {:ok, Path.t()} | {:error, term()}
  def scope_root(scope, opts \\ [])

  def scope_root(:repo, opts) when is_list(opts) do
    cwd = Keyword.get(opts, :repo_root, Keyword.get(opts, :cwd, File.cwd!()))
    find_repo_root(cwd)
  end

  def scope_root(:personal, opts) when is_list(opts) do
    home =
      Keyword.get(opts, :home) ||
        System.get_env("HOME") ||
        System.get_env("USERPROFILE") ||
        System.user_home!()

    {:ok, Path.expand(home)}
  end

  def scope_root(scope, _opts), do: {:error, Errors.invalid_scope(scope)}

  @doc """
  Resolves the canonical plugin root for a scope and plugin name.
  """
  @spec plugin_root(scope(), String.t(), keyword()) :: {:ok, Path.t()} | {:error, term()}
  def plugin_root(scope, plugin_name, opts) when is_binary(plugin_name) and is_list(opts) do
    case Keyword.get(opts, :root, Keyword.get(opts, :plugin_root)) do
      nil ->
        with {:ok, root} <- scope_root(scope, opts) do
          {:ok, Path.join(root, Path.join("plugins", plugin_name))}
        end

      root ->
        {:ok, Path.expand(root)}
    end
  end

  @doc """
  Resolves the canonical marketplace path for a scope.
  """
  @spec marketplace_path(scope(), keyword()) :: {:ok, Path.t()} | {:error, term()}
  def marketplace_path(scope, opts) when is_list(opts) do
    case Keyword.get(opts, :marketplace_path) do
      path when is_binary(path) ->
        {:ok, Path.expand(path)}

      _ ->
        with {:ok, root} <- scope_root(scope, opts) do
          {:ok, Path.join(root, @marketplace_relative_path)}
        end
    end
  end

  @doc """
  Resolves the canonical manifest path for a plugin root or manifest path.
  """
  @spec manifest_path(Path.t()) :: Path.t()
  def manifest_path(path) when is_binary(path) do
    expanded = Path.expand(path)

    if Path.basename(expanded) == "plugin.json" and
         Path.basename(Path.dirname(expanded)) == ".codex-plugin" do
      expanded
    else
      Path.join(expanded, @manifest_relative_path)
    end
  end

  @doc """
  Returns the root directory that owns a canonical marketplace file.
  """
  @spec marketplace_root(Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def marketplace_root(path) when is_binary(path) do
    expanded = Path.expand(path)
    plugins_dir = Path.dirname(expanded)
    dot_agents_dir = Path.dirname(plugins_dir)
    root_dir = Path.dirname(dot_agents_dir)

    cond do
      Path.basename(expanded) != "marketplace.json" ->
        {:error,
         Errors.invalid_marketplace_path(
           expanded,
           "marketplace file must live under `<root>/.agents/plugins/marketplace.json`"
         )}

      Path.basename(plugins_dir) != "plugins" or Path.basename(dot_agents_dir) != ".agents" ->
        {:error,
         Errors.invalid_marketplace_path(
           expanded,
           "marketplace file must live under `<root>/.agents/plugins/marketplace.json`"
         )}

      true ->
        {:ok, root_dir}
    end
  end

  @doc """
  Validates a manifest or marketplace relative path.
  """
  @spec normalize_relative_path(term()) :: {:ok, String.t()} | {:error, String.t()}
  def normalize_relative_path(value) when is_binary(value) do
    path = String.trim(value)

    cond do
      path == "" ->
        {:error, "path must not be empty"}

      not String.starts_with?(path, "./") ->
        {:error, "path must start with `./`"}

      true ->
        relative = String.replace_prefix(path, "./", "")

        cond do
          relative == "" ->
            {:error, "path must not be `./`"}

          Path.type(relative) != :relative ->
            {:error, "path must stay within the plugin root"}

          invalid_component?(relative) ->
            {:error, "path must stay within the plugin root"}

          true ->
            {:ok, path}
        end
    end
  end

  def normalize_relative_path(_value), do: {:error, "expected a relative path string"}

  @doc """
  Validates a marketplace source path before resolving it against the marketplace root.
  """
  @spec normalize_marketplace_source_path(term()) :: {:ok, String.t()} | {:error, String.t()}
  def normalize_marketplace_source_path(value) when is_binary(value) do
    path = String.trim(value)

    cond do
      path == "" ->
        {:error, "path must not be empty"}

      not String.starts_with?(path, "./") ->
        {:error, "path must start with `./`"}

      true ->
        relative = String.replace_prefix(path, "./", "")

        cond do
          relative == "" ->
            {:error, "path must not be `./`"}

          Path.type(relative) != :relative ->
            {:error, "path must resolve relative to the marketplace root"}

          invalid_empty_component?(relative) ->
            {:error, "path must resolve relative to the marketplace root"}

          true ->
            {:ok, path}
        end
    end
  end

  def normalize_marketplace_source_path(_value),
    do: {:error, "expected a relative path string"}

  @doc """
  Resolves a plugin root into a marketplace-relative `./...` source path.
  """
  @spec relative_plugin_source_path(Path.t(), Path.t()) :: {:ok, String.t()} | {:error, term()}
  def relative_plugin_source_path(marketplace_path, plugin_root)
      when is_binary(marketplace_path) and is_binary(plugin_root) do
    with {:ok, root} <- marketplace_root(marketplace_path) do
      expanded_root = Path.expand(root)
      expanded_plugin_root = Path.expand(plugin_root)
      relative = Path.relative_to(expanded_plugin_root, expanded_root)

      cond do
        relative in [".", ""] ->
          {:error,
           Errors.invalid_plugin_root(
             plugin_root,
             "plugin root must not equal the marketplace root"
           )}

        Path.type(relative) == :absolute ->
          {:error,
           Errors.invalid_plugin_root(
             plugin_root,
             "plugin root must stay inside the marketplace root"
           )}

        String.starts_with?(relative, "../") or relative == ".." ->
          {:error,
           Errors.invalid_plugin_root(
             plugin_root,
             "plugin root must stay inside the marketplace root"
           )}

        true ->
          {:ok, "./" <> relative}
      end
    end
  end

  @doc """
  Resolves a marketplace entry source path to an absolute path under its root.
  """
  @spec resolve_marketplace_source_path(Path.t(), String.t()) ::
          {:ok, Path.t()} | {:error, term()}
  def resolve_marketplace_source_path(marketplace_path, source_path)
      when is_binary(marketplace_path) and is_binary(source_path) do
    with {:ok, root} <- marketplace_root(marketplace_path),
         {:ok, normalized} <- normalize_marketplace_source_path(source_path) do
      relative = String.replace_prefix(normalized, "./", "")
      expanded_root = Path.expand(root)
      resolved_path = Path.expand(relative, expanded_root)
      relative_to_root = Path.relative_to(resolved_path, expanded_root)

      cond do
        Path.type(relative_to_root) == :absolute ->
          {:error,
           Errors.invalid_marketplace_source_path(
             marketplace_path,
             source_path,
             "path must stay within the marketplace root"
           )}

        relative_to_root == ".." or String.starts_with?(relative_to_root, "../") ->
          {:error,
           Errors.invalid_marketplace_source_path(
             marketplace_path,
             source_path,
             "path must stay within the marketplace root"
           )}

        true ->
          {:ok, resolved_path}
      end
    else
      {:error, message} when is_binary(message) ->
        {:error, Errors.invalid_marketplace_source_path(marketplace_path, source_path, message)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_repo_root(path) when is_binary(path) do
    expanded =
      path
      |> Path.expand()
      |> then(fn candidate ->
        if File.dir?(candidate), do: candidate, else: Path.dirname(candidate)
      end)

    do_find_repo_root(expanded)
  end

  defp do_find_repo_root(path) do
    cond do
      File.exists?(Path.join(path, ".git")) ->
        {:ok, path}

      Path.dirname(path) == path ->
        {:error, Errors.repo_root_not_found(path)}

      true ->
        do_find_repo_root(Path.dirname(path))
    end
  end

  defp invalid_component?(relative_path) do
    relative_path
    |> Path.split()
    |> Enum.any?(&(&1 in [".", "..", ""]))
  end

  defp invalid_empty_component?(relative_path) do
    relative_path
    |> Path.split()
    |> Enum.any?(&(&1 in [".", ""]))
  end
end
