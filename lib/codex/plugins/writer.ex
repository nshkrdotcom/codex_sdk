defmodule Codex.Plugins.Writer do
  @moduledoc false

  alias Codex.Plugins.{Errors, Manifest, Marketplace, Paths, Reader}

  @type write_manifest_error :: Errors.file_exists_error() | Errors.io_error()
  @type add_marketplace_plugin_result :: %{
          marketplace_path: String.t(),
          marketplace: Marketplace.t(),
          plugin_name: String.t()
        }

  @spec write_manifest(String.t(), Manifest.t(), keyword()) ::
          :ok | {:error, write_manifest_error()}
  def write_manifest(path, %Manifest{} = manifest, opts \\ [])
      when is_binary(path) and is_list(opts) do
    manifest_path = Paths.manifest_path(path)
    payload = Manifest.to_map(manifest)

    with {:ok, json} <- encode_json(payload),
         :ok <- prepare_parent(manifest_path, opts) do
      write_file(manifest_path, json, opts)
    end
  end

  @spec write_marketplace(String.t(), Marketplace.t(), keyword()) :: :ok | {:error, term()}
  def write_marketplace(path, %Marketplace{} = marketplace, opts \\ [])
      when is_binary(path) and is_list(opts) do
    marketplace_path = Path.expand(path)

    with {:ok, _root} <- Paths.marketplace_root(marketplace_path),
         {:ok, final_marketplace} <- maybe_merge_marketplace(marketplace_path, marketplace, opts),
         :ok <- Reader.validate_marketplace_sources(marketplace_path, final_marketplace),
         {:ok, json} <- encode_json(Marketplace.to_map(final_marketplace)),
         :ok <- prepare_parent(marketplace_path, opts) do
      write_file(
        marketplace_path,
        json,
        Keyword.put(
          opts,
          :overwrite,
          Keyword.get(opts, :overwrite, false) or Keyword.get(opts, :merge, false)
        )
      )
    end
  end

  @spec add_marketplace_plugin(String.t(), Marketplace.plugin_t(), keyword()) ::
          {:ok, add_marketplace_plugin_result()} | {:error, term()}
  def add_marketplace_plugin(path, plugin, opts \\ [])
      when is_binary(path) and is_map(plugin) and is_list(opts) do
    marketplace_path = Path.expand(path)
    overwrite? = Keyword.get(opts, :overwrite, false)

    with {:ok, _root} <- Paths.marketplace_root(marketplace_path),
         {:ok, marketplace} <- load_or_initialize_marketplace(marketplace_path, opts),
         {:ok, updated_marketplace} <-
           Marketplace.put_plugin(marketplace, plugin, overwrite: overwrite?),
         :ok <- Reader.validate_marketplace_sources(marketplace_path, updated_marketplace),
         :ok <-
           write_marketplace(marketplace_path, updated_marketplace,
             create_parents: true,
             overwrite: true
           ) do
      {:ok,
       %{
         marketplace_path: marketplace_path,
         marketplace: updated_marketplace,
         plugin_name: plugin.name
       }}
    else
      {:error, {:plugin_conflict, %{plugin_name: plugin_name}}} ->
        {:error, Errors.plugin_conflict(marketplace_path, plugin_name)}

      {:error, _reason} = error ->
        error
    end
  end

  @spec encode_json(map()) :: {:ok, String.t()}
  def encode_json(map) when is_map(map), do: {:ok, encode_value(map, 0) <> "\n"}

  defp maybe_merge_marketplace(path, marketplace, opts) do
    if Keyword.get(opts, :merge, false) and File.exists?(path) do
      with {:ok, existing} <- Reader.read_marketplace(path),
           {:ok, merged} <-
             Marketplace.merge(existing, marketplace,
               overwrite: Keyword.get(opts, :overwrite, false)
             ) do
        {:ok, merged}
      else
        {:error, {:plugin_conflict, %{plugin_name: plugin_name}}} ->
          {:error, Errors.plugin_conflict(path, plugin_name)}

        {:error, _reason} = error ->
          error
      end
    else
      {:ok, marketplace}
    end
  end

  defp load_or_initialize_marketplace(path, opts) do
    if File.exists?(path) do
      Reader.read_marketplace(path)
    else
      build_default_marketplace(path, opts)
    end
  end

  defp build_default_marketplace(path, opts) do
    with {:ok, root} <- Paths.marketplace_root(path) do
      Marketplace.parse(%{
        "name" => Keyword.get(opts, :marketplace_name) || default_marketplace_name(root),
        "interface" => %{
          "displayName" =>
            Keyword.get(opts, :marketplace_display_name) ||
              default_marketplace_display_name(root)
        },
        "plugins" => []
      })
    end
  end

  defp default_marketplace_name(root) do
    case Path.basename(root) do
      "" -> "local-marketplace"
      "/" -> "local-marketplace"
      basename -> "#{basename}-local"
    end
  end

  defp default_marketplace_display_name(root) do
    case Path.basename(root) do
      "" -> "Local Plugins"
      "/" -> "Local Plugins"
      basename -> "#{humanize_name(basename)} Plugins"
    end
  end

  defp prepare_parent(path, opts) do
    if Keyword.get(opts, :create_parents, false) do
      case File.mkdir_p(Path.dirname(path)) do
        :ok -> :ok
        {:error, reason} -> {:error, Errors.io(:mkdir, Path.dirname(path), reason)}
      end
    else
      :ok
    end
  end

  defp write_file(path, contents, opts) do
    overwrite? = Keyword.get(opts, :overwrite, false)

    if File.exists?(path) and not overwrite? do
      {:error, Errors.file_exists(path)}
    else
      do_write_file(path, contents)
    end
  end

  defp do_write_file(path, contents) do
    temp_path = "#{path}.tmp-#{System.unique_integer([:positive])}"

    with :ok <- File.write(temp_path, contents),
         :ok <- File.rename(temp_path, path) do
      :ok
    else
      {:error, reason} ->
        _ = File.rm(temp_path)
        {:error, Errors.io(:write, path, reason)}
    end
  end

  defp encode_value(map, indent) when is_map(map) do
    if map_size(map) == 0 do
      "{}"
    else
      next_indent = indent + 2

      entries =
        map
        |> Enum.map(fn {key, value} -> {encode_key(key), value} end)
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(fn {key, value} ->
          indent(next_indent) <> Jason.encode!(key) <> ": " <> encode_value(value, next_indent)
        end)

      "{\n" <> Enum.join(entries, ",\n") <> "\n" <> indent(indent) <> "}"
    end
  end

  defp encode_value(list, indent) when is_list(list) do
    if list == [] do
      "[]"
    else
      next_indent = indent + 2

      entries =
        Enum.map(list, fn value ->
          indent(next_indent) <> encode_value(value, next_indent)
        end)

      "[\n" <> Enum.join(entries, ",\n") <> "\n" <> indent(indent) <> "]"
    end
  end

  defp encode_value(value, _indent) when is_binary(value), do: Jason.encode!(value)
  defp encode_value(value, _indent) when is_number(value), do: Jason.encode!(value)
  defp encode_value(true, _indent), do: "true"
  defp encode_value(false, _indent), do: "false"
  defp encode_value(nil, _indent), do: "null"
  defp encode_value(value, _indent) when is_atom(value), do: Jason.encode!(Atom.to_string(value))

  defp encode_key(key) when is_binary(key), do: key
  defp encode_key(key) when is_atom(key), do: Atom.to_string(key)
  defp encode_key(key), do: to_string(key)

  defp indent(size), do: String.duplicate(" ", size)

  defp humanize_name(name) when is_binary(name) do
    Codex.StringScan.humanize_separated(name)
  end
end
