defmodule Codex.Plugins.Errors do
  @moduledoc false

  @type io_error :: {:plugin_io, %{action: atom(), path: String.t(), reason: term()}}
  @type invalid_json_error ::
          {:invalid_plugin_json, %{path: String.t(), reason: String.t(), raw_reason: term()}}
  @type file_exists_error :: {:plugin_file_exists, %{path: String.t()}}
  @type repo_root_not_found_error :: {:repo_root_not_found, %{cwd: String.t()}}
  @type invalid_scope_error :: {:invalid_plugin_scope, %{scope: term()}}
  @type invalid_plugin_name_error ::
          {:invalid_plugin_name, %{name: term(), message: String.t()}}
  @type invalid_plugin_root_error ::
          {:invalid_plugin_root, %{path: String.t(), message: String.t()}}
  @type invalid_marketplace_path_error ::
          {:invalid_marketplace_path, %{path: String.t(), message: String.t()}}
  @type invalid_marketplace_source_path_error ::
          {:invalid_marketplace_source_path,
           %{path: String.t(), source_path: String.t(), message: String.t()}}
  @type plugin_conflict_error ::
          {:plugin_conflict, %{path: String.t(), plugin_name: String.t()}}

  @type t ::
          io_error()
          | invalid_json_error()
          | file_exists_error()
          | repo_root_not_found_error()
          | invalid_scope_error()
          | invalid_plugin_name_error()
          | invalid_plugin_root_error()
          | invalid_marketplace_path_error()
          | invalid_marketplace_source_path_error()
          | plugin_conflict_error()

  @spec io(atom(), String.t(), term()) :: io_error()
  def io(action, path, reason) when is_atom(action) and is_binary(path) do
    {:plugin_io, %{action: action, path: Path.expand(path), reason: reason}}
  end

  @spec invalid_json(String.t(), term()) :: invalid_json_error()
  def invalid_json(path, reason) when is_binary(path) do
    {:invalid_plugin_json,
     %{path: Path.expand(path), reason: format_reason(reason), raw_reason: reason}}
  end

  @spec file_exists(String.t()) :: file_exists_error()
  def file_exists(path) when is_binary(path),
    do: {:plugin_file_exists, %{path: Path.expand(path)}}

  @spec repo_root_not_found(String.t()) :: repo_root_not_found_error()
  def repo_root_not_found(path) when is_binary(path),
    do: {:repo_root_not_found, %{cwd: Path.expand(path)}}

  @spec invalid_scope(term()) :: invalid_scope_error()
  def invalid_scope(scope), do: {:invalid_plugin_scope, %{scope: scope}}

  @spec invalid_plugin_name(term(), String.t()) :: invalid_plugin_name_error()
  def invalid_plugin_name(name, message),
    do: {:invalid_plugin_name, %{name: name, message: message}}

  @spec invalid_plugin_root(String.t(), String.t()) :: invalid_plugin_root_error()
  def invalid_plugin_root(path, message) when is_binary(path),
    do: {:invalid_plugin_root, %{path: Path.expand(path), message: message}}

  @spec invalid_marketplace_path(String.t(), String.t()) :: invalid_marketplace_path_error()
  def invalid_marketplace_path(path, message) when is_binary(path),
    do: {:invalid_marketplace_path, %{path: Path.expand(path), message: message}}

  @spec invalid_marketplace_source_path(String.t(), String.t(), String.t()) ::
          invalid_marketplace_source_path_error()
  def invalid_marketplace_source_path(path, source_path, message)
      when is_binary(path) and is_binary(source_path) do
    {:invalid_marketplace_source_path,
     %{path: Path.expand(path), source_path: source_path, message: message}}
  end

  @spec plugin_conflict(String.t(), String.t()) :: plugin_conflict_error()
  def plugin_conflict(path, plugin_name) when is_binary(path) and is_binary(plugin_name) do
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
