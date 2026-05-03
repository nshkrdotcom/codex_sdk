defmodule Codex.TestSupport.TempDir do
  @moduledoc false

  @max_attempts 32

  def create!(prefix) when is_binary(prefix) do
    prefix
    |> sanitize_prefix()
    |> create_unique!(@max_attempts)
  end

  defp create_unique!(_prefix, 0) do
    raise "unable to allocate a unique temporary directory"
  end

  defp create_unique!(prefix, attempts_left) when attempts_left > 0 do
    path = Path.join(System.tmp_dir!(), "#{prefix}_#{unique_suffix()}")

    case File.mkdir(path) do
      :ok ->
        path

      {:error, :eexist} ->
        create_unique!(prefix, attempts_left - 1)

      {:error, reason} ->
        raise "unable to create temporary directory #{inspect(path)}: #{inspect(reason)}"
    end
  end

  defp sanitize_prefix(prefix) do
    prefix
    |> to_string()
    |> String.trim()
    |> scan_prefix([])
    |> case do
      "" -> "codex_tmp"
      sanitized -> sanitized
    end
  end

  defp scan_prefix(<<byte, rest::binary>>, acc)
       when byte in ?A..?Z or byte in ?a..?z or byte in ?0..?9 or byte in [?_, ?-] do
    scan_prefix(rest, [<<byte>> | acc])
  end

  defp scan_prefix(<<_byte, rest::binary>>, acc), do: scan_prefix(rest, ["_" | acc])
  defp scan_prefix(<<>>, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp unique_suffix do
    Base.encode16(:crypto.strong_rand_bytes(10), case: :lower)
  end
end
