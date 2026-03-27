defmodule Codex.Plugins.Reader do
  @moduledoc false

  alias Codex.Plugins.{Errors, Manifest, Marketplace, Paths}

  @spec read_manifest(String.t()) :: {:ok, Manifest.t()} | {:error, term()}
  def read_manifest(path) when is_binary(path) do
    manifest_path = Paths.manifest_path(path)

    with {:ok, contents} <- read_file(manifest_path),
         {:ok, decoded} <- decode_json(manifest_path, contents) do
      Manifest.parse(decoded)
    end
  end

  @spec read_marketplace(String.t()) :: {:ok, Marketplace.t()} | {:error, term()}
  def read_marketplace(path) when is_binary(path) do
    marketplace_path = Path.expand(path)

    with {:ok, _root} <- Paths.marketplace_root(marketplace_path),
         {:ok, contents} <- read_file(marketplace_path),
         {:ok, decoded} <- decode_json(marketplace_path, contents),
         {:ok, marketplace} <- Marketplace.parse(decoded),
         :ok <- validate_marketplace_sources(marketplace_path, marketplace) do
      {:ok, marketplace}
    end
  end

  @spec validate_marketplace_sources(String.t(), Marketplace.t()) :: :ok | {:error, term()}
  def validate_marketplace_sources(marketplace_path, %Marketplace{plugins: plugins}) do
    Enum.reduce_while(plugins, :ok, fn plugin, :ok ->
      case Paths.resolve_marketplace_source_path(marketplace_path, plugin.source.path) do
        {:ok, _resolved_path} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, contents} -> {:ok, contents}
      {:error, reason} -> {:error, Errors.io(:read, path, reason)}
    end
  end

  defp decode_json(path, contents) do
    case Jason.decode(contents) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, error} -> {:error, Errors.invalid_json(path, error)}
    end
  end
end
