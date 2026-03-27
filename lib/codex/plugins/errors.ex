defmodule Codex.Plugins.Errors do
  @moduledoc false

  @spec io(atom(), Path.t(), term()) :: {:plugin_io, map()}
  def io(action, path, reason) when is_atom(action) do
    {:plugin_io, %{action: action, path: Path.expand(path), reason: reason}}
  end

  @spec invalid_json(Path.t(), term()) :: {:invalid_plugin_json, map()}
  def invalid_json(path, reason) do
    {:invalid_plugin_json,
     %{path: Path.expand(path), reason: format_reason(reason), raw_reason: reason}}
  end

  @spec file_exists(Path.t()) :: {:plugin_file_exists, map()}
  def file_exists(path), do: {:plugin_file_exists, %{path: Path.expand(path)}}

  @spec repo_root_not_found(Path.t()) :: {:repo_root_not_found, map()}
  def repo_root_not_found(path), do: {:repo_root_not_found, %{cwd: Path.expand(path)}}

  @spec invalid_scope(term()) :: {:invalid_plugin_scope, map()}
  def invalid_scope(scope), do: {:invalid_plugin_scope, %{scope: scope}}

  @spec invalid_plugin_name(term(), String.t()) :: {:invalid_plugin_name, map()}
  def invalid_plugin_name(name, message),
    do: {:invalid_plugin_name, %{name: name, message: message}}

  @spec invalid_plugin_root(Path.t(), String.t()) :: {:invalid_plugin_root, map()}
  def invalid_plugin_root(path, message),
    do: {:invalid_plugin_root, %{path: Path.expand(path), message: message}}

  @spec invalid_marketplace_path(Path.t(), String.t()) :: {:invalid_marketplace_path, map()}
  def invalid_marketplace_path(path, message),
    do: {:invalid_marketplace_path, %{path: Path.expand(path), message: message}}

  @spec invalid_marketplace_source_path(Path.t(), String.t(), String.t()) ::
          {:invalid_marketplace_source_path, map()}
  def invalid_marketplace_source_path(path, source_path, message) do
    {:invalid_marketplace_source_path,
     %{path: Path.expand(path), source_path: source_path, message: message}}
  end

  @spec plugin_conflict(Path.t(), String.t()) :: {:plugin_conflict, map()}
  def plugin_conflict(path, plugin_name) do
    {:plugin_conflict, %{path: Path.expand(path), plugin_name: plugin_name}}
  end

  defp format_reason(%{message: message}) when is_binary(message), do: message
  defp format_reason(reason) when is_binary(reason), do: reason

  defp format_reason(reason) do
    Exception.message(reason)
  rescue
    _ -> inspect(reason)
  end
end
