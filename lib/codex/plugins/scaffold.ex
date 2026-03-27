defmodule Codex.Plugins.Scaffold do
  @moduledoc false

  alias Codex.Plugins.{Errors, Manifest, Marketplace, Paths, Reader, Writer}

  @default_category "Productivity"

  @spec scaffold(keyword()) :: {:ok, map()} | {:error, term()}
  def scaffold(opts) when is_list(opts) do
    with {:ok, scope} <- normalize_scope(Keyword.get(opts, :scope, :repo)),
         {:ok, plugin_name} <-
           normalize_plugin_name(Keyword.get(opts, :plugin_name, Keyword.get(opts, :name))),
         {:ok, plugin_root} <-
           Paths.plugin_root(scope, plugin_name, Keyword.put(opts, :plugin_name, plugin_name)),
         manifest_path = Paths.manifest_path(plugin_root),
         {:ok, skill} <- normalize_skill(Keyword.get(opts, :skill)),
         :ok <- preflight_files(manifest_path, skill_path(plugin_root, skill), opts),
         :ok <- preflight_marketplace(scope, plugin_name, plugin_root, opts),
         {:ok, manifest} <- build_manifest(plugin_name, skill, opts),
         :ok <-
           Writer.write_manifest(manifest_path, manifest,
             create_parents: true,
             overwrite: Keyword.get(opts, :overwrite, false)
           ),
         :ok <- maybe_write_skill(plugin_root, skill, opts),
         {:ok, marketplace_result} <- maybe_add_marketplace(scope, plugin_name, plugin_root, opts) do
      {:ok,
       %{
         scope: scope,
         plugin_name: plugin_name,
         plugin_root: plugin_root,
         manifest_path: manifest_path,
         manifest: manifest,
         skill_paths: skill_paths(plugin_root, skill),
         marketplace_path: marketplace_result[:marketplace_path],
         marketplace: marketplace_result[:marketplace],
         created_paths:
           [
             manifest_path,
             marketplace_result[:marketplace_path] | skill_paths(plugin_root, skill)
           ]
           |> Enum.reject(&is_nil/1)
       }}
    end
  end

  defp normalize_scope(scope) when scope in [:repo, :personal], do: {:ok, scope}
  defp normalize_scope(scope), do: {:error, Errors.invalid_scope(scope)}

  defp normalize_plugin_name(nil),
    do: {:error, Errors.invalid_plugin_name(nil, "plugin_name is required")}

  defp normalize_plugin_name(name) when is_binary(name) do
    normalized =
      name
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "-")
      |> String.trim("-")
      |> String.replace(~r/-+/, "-")

    if normalized == "" do
      {:error,
       Errors.invalid_plugin_name(name, "plugin_name must include at least one letter or digit")}
    else
      {:ok, normalized}
    end
  end

  defp normalize_plugin_name(name),
    do: {:error, Errors.invalid_plugin_name(name, "plugin_name must be a string")}

  defp normalize_skill(nil), do: {:ok, nil}
  defp normalize_skill(false), do: {:ok, nil}

  defp normalize_skill(skill) when is_list(skill),
    do: skill |> Enum.into(%{}) |> normalize_skill()

  defp normalize_skill(%{} = skill) do
    case normalize_plugin_name(Map.get(skill, :name) || Map.get(skill, "name")) do
      {:ok, name} ->
        {:ok,
         %{
           name: name,
           description:
             Map.get(skill, :description) ||
               Map.get(skill, "description") ||
               "Describe what this skill does."
         }}

      {:error, _reason} = error ->
        error
    end
  end

  defp preflight_files(manifest_path, skill_path, opts) do
    overwrite? = Keyword.get(opts, :overwrite, false)

    cond do
      File.exists?(manifest_path) and not overwrite? ->
        {:error, Errors.file_exists(manifest_path)}

      is_binary(skill_path) and File.exists?(skill_path) and not overwrite? ->
        {:error, Errors.file_exists(skill_path)}

      true ->
        :ok
    end
  end

  defp preflight_marketplace(scope, plugin_name, plugin_root, opts) do
    if Keyword.get(opts, :with_marketplace, false) and not Keyword.get(opts, :overwrite, false) do
      marketplace_scope = Keyword.get(opts, :marketplace_scope, scope)

      with {:ok, marketplace_path} <- Paths.marketplace_path(marketplace_scope, opts),
           {:ok, _source_path} <- Paths.relative_plugin_source_path(marketplace_path, plugin_root) do
        if File.exists?(marketplace_path) do
          with {:ok, marketplace} <- Reader.read_marketplace(marketplace_path) do
            if Enum.any?(marketplace.plugins, &(&1.name == plugin_name)) do
              {:error, Errors.plugin_conflict(marketplace_path, plugin_name)}
            else
              :ok
            end
          end
        else
          :ok
        end
      end
    else
      :ok
    end
  end

  defp build_manifest(plugin_name, skill, opts) do
    category = Keyword.get(opts, :category, @default_category)
    interface_defaults = %{"displayName" => humanize_name(plugin_name), "category" => category}
    manifest_defaults = %{"name" => plugin_name, "interface" => interface_defaults}

    manifest_defaults =
      if skill, do: Map.put(manifest_defaults, "skills", "./skills"), else: manifest_defaults

    overrides = Keyword.get(opts, :manifest, %{})

    manifest_defaults
    |> deep_merge(normalize_override_map(overrides))
    |> Manifest.parse()
  end

  defp maybe_write_skill(_plugin_root, nil, _opts), do: :ok

  defp maybe_write_skill(plugin_root, skill, opts) do
    skill_path = skill_path(plugin_root, skill)

    case File.mkdir_p(Path.dirname(skill_path)) do
      :ok ->
        if File.exists?(skill_path) and not Keyword.get(opts, :overwrite, false) do
          {:error, Errors.file_exists(skill_path)}
        else
          case File.write(
                 skill_path,
                 """
                 ---
                 name: #{skill.name}
                 description: #{skill.description}
                 ---

                 # #{humanize_name(skill.name)}

                 #{skill.description}
                 """
               ) do
            :ok -> :ok
            {:error, reason} -> {:error, Errors.io(:write, skill_path, reason)}
          end
        end

      {:error, reason} ->
        {:error, Errors.io(:mkdir, Path.dirname(skill_path), reason)}
    end
  end

  defp maybe_add_marketplace(scope, plugin_name, plugin_root, opts) do
    if Keyword.get(opts, :with_marketplace, false) do
      marketplace_scope = Keyword.get(opts, :marketplace_scope, scope)

      with {:ok, marketplace_path} <- Paths.marketplace_path(marketplace_scope, opts),
           {:ok, source_path} <- Paths.relative_plugin_source_path(marketplace_path, plugin_root),
           {:ok, plugin} <- build_marketplace_plugin(plugin_name, source_path, opts),
           {:ok, result} <-
             Writer.add_marketplace_plugin(
               marketplace_path,
               plugin,
               overwrite: Keyword.get(opts, :overwrite, false),
               create_parents: true,
               marketplace_name: Keyword.get(opts, :marketplace_name),
               marketplace_display_name: Keyword.get(opts, :marketplace_display_name)
             ) do
        {:ok, result}
      end
    else
      {:ok, %{}}
    end
  end

  defp build_marketplace_plugin(plugin_name, source_path, opts) do
    category = Keyword.get(opts, :category, @default_category)

    Marketplace.parse_plugin(
      name: plugin_name,
      source: [source: :local, path: source_path],
      policy:
        [
          installation: Keyword.get(opts, :installation, :available),
          authentication: Keyword.get(opts, :authentication, :on_install)
        ] ++ maybe_products(opts),
      category: category
    )
  end

  defp maybe_products(opts) do
    case Keyword.get(opts, :products) do
      nil -> []
      products -> [products: products]
    end
  end

  defp normalize_override_map(nil), do: %{}
  defp normalize_override_map(map) when is_map(map), do: map
  defp normalize_override_map(list) when is_list(list), do: Enum.into(list, %{})

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn
      _key, %{} = left_map, %{} = right_map -> deep_merge(left_map, right_map)
      _key, _left_value, right_value -> right_value
    end)
  end

  defp skill_path(_plugin_root, nil), do: nil

  defp skill_path(plugin_root, skill),
    do: Path.join(plugin_root, Path.join(["skills", skill.name, "SKILL.md"]))

  defp skill_paths(_plugin_root, nil), do: []
  defp skill_paths(plugin_root, skill), do: [skill_path(plugin_root, skill)]

  defp humanize_name(name) when is_binary(name) do
    name
    |> String.split("-", trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
