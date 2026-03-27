defmodule Codex.Plugins do
  @moduledoc """
  Local plugin authoring helpers for manifests, marketplaces, and scaffold flows.

  This namespace is intentionally separate from the app-server runtime APIs on
  `Codex.AppServer`. Use `Codex.Plugins.*` to author files locally with normal
  Elixir file IO. Use `Codex.AppServer.plugin_*` only when you want runtime
  discovery, read, install, or uninstall verification against a running Codex
  app-server.
  """

  alias Codex.Plugins.{Manifest, Marketplace, Reader, Scaffold, Writer}

  @type scaffold_result :: %{
          scope: Codex.Plugins.Paths.scope(),
          plugin_name: String.t(),
          plugin_root: String.t(),
          manifest_path: String.t(),
          manifest: Manifest.t(),
          skill_paths: [String.t()],
          marketplace_path: String.t() | nil,
          marketplace: Marketplace.t() | nil,
          created_paths: [String.t()]
        }

  @type scaffold_error ::
          {:plugin_io, %{action: atom(), path: String.t(), reason: term()}}
          | {:invalid_plugin_json, %{path: String.t(), reason: String.t(), raw_reason: term()}}
          | {:plugin_file_exists, %{path: String.t()}}
          | {:repo_root_not_found, %{cwd: String.t()}}
          | {:invalid_plugin_scope, %{scope: term()}}
          | {:invalid_plugin_name, %{name: term(), message: String.t()}}
          | {:invalid_plugin_root, %{path: String.t(), message: String.t()}}
          | {:invalid_marketplace_path, %{path: String.t(), message: String.t()}}
          | {:invalid_marketplace_source_path,
             %{path: String.t(), source_path: String.t(), message: String.t()}}
          | {:plugin_conflict, %{path: String.t(), plugin_name: String.t()}}
          | {:invalid_plugin_manifest, CliSubprocessCore.Schema.error_detail()}
          | {:invalid_plugin_marketplace, CliSubprocessCore.Schema.error_detail()}
          | {:invalid_plugin_marketplace_plugin, CliSubprocessCore.Schema.error_detail()}

  @doc """
  Builds and validates a manifest struct.
  """
  @spec new_manifest(map() | keyword() | Manifest.t()) ::
          {:ok, Manifest.t()} | {:error, term()}
  def new_manifest(attrs), do: Manifest.parse(attrs)

  @doc """
  Validates manifest data and returns normalized issues on failure.
  """
  @spec validate_manifest(map() | keyword() | Manifest.t()) :: :ok | {:error, [map()]}
  def validate_manifest(attrs) do
    attrs
    |> Manifest.parse()
    |> to_validation_result()
  end

  @doc """
  Builds and validates a marketplace struct.
  """
  @spec new_marketplace(map() | keyword() | Marketplace.t()) ::
          {:ok, Marketplace.t()} | {:error, term()}
  def new_marketplace(attrs), do: Marketplace.parse(attrs)

  @doc """
  Validates marketplace data and returns normalized issues on failure.
  """
  @spec validate_marketplace(map() | keyword() | Marketplace.t()) :: :ok | {:error, [map()]}
  def validate_marketplace(attrs) do
    attrs
    |> Marketplace.parse()
    |> to_validation_result()
  end

  @doc """
  Reads and validates a local plugin manifest.
  """
  @spec read_manifest(Path.t()) :: {:ok, Manifest.t()} | {:error, term()}
  def read_manifest(path), do: Reader.read_manifest(path)

  @doc """
  Reads and validates a local marketplace file.
  """
  @spec read_marketplace(Path.t()) :: {:ok, Marketplace.t()} | {:error, term()}
  def read_marketplace(path), do: Reader.read_marketplace(path)

  @doc """
  Writes a manifest deterministically using local file IO.
  """
  @spec write_manifest(Path.t(), map() | keyword() | Manifest.t(), keyword()) ::
          :ok | {:error, term()}
  def write_manifest(path, manifest, opts \\ []) do
    with {:ok, manifest} <- Manifest.parse(manifest) do
      Writer.write_manifest(path, manifest, opts)
    end
  end

  @doc """
  Writes a marketplace deterministically using local file IO.
  """
  @spec write_marketplace(Path.t(), map() | keyword() | Marketplace.t(), keyword()) ::
          :ok | {:error, term()}
  def write_marketplace(path, marketplace, opts \\ []) do
    with {:ok, marketplace} <- Marketplace.parse(marketplace) do
      Writer.write_marketplace(path, marketplace, opts)
    end
  end

  @doc """
  Safely appends or replaces one marketplace entry without erasing unrelated entries.
  """
  @spec add_marketplace_plugin(Path.t(), map() | keyword(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def add_marketplace_plugin(path, plugin, opts \\ []) do
    with {:ok, plugin} <- Marketplace.parse_plugin(plugin) do
      Writer.add_marketplace_plugin(path, plugin, opts)
    end
  end

  @doc """
  Scaffolds a minimal local plugin tree.
  """
  @spec scaffold(keyword()) :: {:ok, scaffold_result()} | {:error, scaffold_error()}
  def scaffold(opts), do: Scaffold.scaffold(opts)

  defp to_validation_result({:ok, _struct}), do: :ok
  defp to_validation_result({:error, {_tag, details}}), do: {:error, details.issues}
end
