defmodule Codex.OutputSchemaFile do
  @moduledoc """
  Persists structured output schemas to temporary JSON files so they can be passed to the
  Codex CLI. Returns the generated path alongside a cleanup function for RAII-style usage.
  """

  @schema_prefix "codex_output_schema"

  @doc """
  Persists the provided schema to a temporary JSON file and returns `{path, cleanup_fun}`.

  The schema may be any JSON-encodable term (map, list, primitive). When `nil` is supplied
  no file is created and the return path is `nil`.
  """
  @spec create(term()) :: {:ok, String.t() | nil, (-> :ok)} | {:error, term()}
  def create(schema) do
    case encode(schema) do
      {:ok, encoded} -> create_encoded(encoded)
      {:error, _} = error -> error
    end
  end

  @doc false
  @spec encode(term()) :: {:ok, String.t() | nil} | {:error, term()}
  def encode(nil), do: {:ok, nil}

  def encode(schema) do
    Jason.encode(schema)
  rescue
    error -> {:error, error}
  end

  @doc false
  @spec create_encoded(String.t() | nil) :: {:ok, String.t() | nil, (-> :ok)} | {:error, term()}
  def create_encoded(nil), do: {:ok, nil, fn -> :ok end}

  def create_encoded(encoded) when is_binary(encoded) do
    path =
      System.tmp_dir!()
      |> Path.join(@schema_prefix <> "_" <> unique_id() <> ".json")

    File.write!(path, encoded)

    {:ok, path, fn -> cleanup_file(path) end}
  rescue
    error -> {:error, error}
  end

  @doc false
  defp cleanup_file(path) do
    File.rm(path)
    :ok
  end

  defp unique_id do
    System.unique_integer([:positive])
    |> Integer.to_string()
  end
end
