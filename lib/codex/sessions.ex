defmodule Codex.Sessions do
  @moduledoc """
  Helpers for inspecting Codex CLI session files.
  """

  @default_sessions_dir Path.expand("~/.codex/sessions")

  @type session_entry :: %{
          id: String.t(),
          path: String.t(),
          started_at: String.t() | nil,
          updated_at: String.t() | nil,
          cwd: String.t() | nil,
          originator: String.t() | nil,
          cli_version: String.t() | nil
        }

  @doc """
  Lists known sessions by scanning the sessions directory.

  ## Options

  - `:sessions_dir` - Override the default session directory.
  """
  @spec list_sessions(keyword()) :: {:ok, [session_entry()]} | {:error, term()}
  def list_sessions(opts \\ []) do
    sessions_dir = Keyword.get(opts, :sessions_dir, @default_sessions_dir)

    case File.stat(sessions_dir) do
      {:ok, %File.Stat{type: :directory}} -> {:ok, collect_entries(sessions_dir)}
      {:error, :enoent} -> {:ok, []}
      {:ok, _} -> {:error, :not_a_directory}
      {:error, reason} -> {:error, reason}
    end
  end

  defp collect_entries(sessions_dir) do
    sessions_dir
    |> session_files()
    |> Enum.map(&build_entry/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(& &1.updated_at, :desc)
  end

  defp session_files(sessions_dir) do
    jsonl = Path.wildcard(Path.join(sessions_dir, "**/*.jsonl"))
    json = Path.wildcard(Path.join(sessions_dir, "**/*.json"))
    Enum.uniq(jsonl ++ json)
  end

  defp build_entry(path) do
    with {:ok, line} <- read_first_line(path) do
      meta = decode_session_meta(line)

      %{
        id: meta.id || fallback_id(path),
        path: path,
        started_at: meta.started_at,
        updated_at: stat_updated_at(path),
        cwd: meta.cwd,
        originator: meta.originator,
        cli_version: meta.cli_version
      }
    end
  end

  defp read_first_line(path) do
    case File.open(path, [:read]) do
      {:ok, io} ->
        line = IO.read(io, :line)
        File.close(io)

        if line == :eof do
          {:error, :empty}
        else
          {:ok, line}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_session_meta(line) when is_binary(line) do
    line
    |> String.trim()
    |> parse_session_line()
  end

  defp parse_session_line(""), do: %{}

  defp parse_session_line(line) do
    case Jason.decode(line) do
      {:ok, raw} when is_map(raw) -> build_session_meta(raw)
      _ -> %{}
    end
  end

  defp build_session_meta(raw) do
    payload = Map.get(raw, "payload", %{})

    %{
      id: first_present([payload["id"], payload["thread_id"], raw["id"], raw["thread_id"]]),
      started_at: first_present([payload["timestamp"], raw["timestamp"]]),
      cwd: first_present([payload["cwd"], raw["cwd"]]),
      originator: first_present([payload["originator"], raw["originator"]]),
      cli_version: first_present([payload["cli_version"], raw["cli_version"]])
    }
  end

  defp first_present(values) do
    Enum.find(values, fn value -> not is_nil(value) end)
  end

  defp fallback_id(path) do
    basename = Path.basename(path)

    basename
    |> String.replace_suffix(".jsonl", "")
    |> String.replace_suffix(".json", "")
  end

  defp stat_updated_at(path) do
    with {:ok, %File.Stat{mtime: mtime}} <- File.stat(path),
         {:ok, naive} <- NaiveDateTime.from_erl(mtime) do
      NaiveDateTime.to_iso8601(naive)
    else
      _ -> nil
    end
  end
end
