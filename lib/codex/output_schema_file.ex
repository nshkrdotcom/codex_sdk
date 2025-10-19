defmodule Codex.OutputSchemaFile do
  @moduledoc false

  @schema_prefix "codex_output_schema"

  @doc """
  Persists the provided schema to a temporary JSON file and returns `{path, cleanup_fun}`.

  The schema may be any JSON-encodable term (map, list, primitive). When `nil` is supplied
  no file is created and the return path is `nil`.
  """
  @spec create(term()) :: {:ok, String.t() | nil, (-> :ok)} | {:error, term()}
  def create(nil), do: {:ok, nil, fn -> :ok end}

  def create(schema) do
    with {:ok, encoded} <- Jason.encode(schema) do
      path =
        System.tmp_dir!()
        |> Path.join(@schema_prefix <> "_" <> unique_id() <> ".json")

      File.write!(path, encoded)

      {:ok, path, fn -> cleanup_file(path) end}
    end
  rescue
    error -> {:error, error}
  end

  defp cleanup_file(path) do
    File.rm(path)
    :ok
  end

  defp unique_id do
    System.unique_integer([:positive])
    |> Integer.to_string()
  end
end
