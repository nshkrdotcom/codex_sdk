defmodule Codex.StringScan do
  @moduledoc false

  @ascii_whitespace [" ", "\n", "\r", "\t", "\v", "\f"]

  def split_ascii_whitespace(value) when is_binary(value) do
    String.split(value, @ascii_whitespace, trim: true)
  end

  def split_ascii_whitespace(_value), do: []

  def collapse_ascii_whitespace(value, separator \\ " ") when is_binary(value) do
    value
    |> split_ascii_whitespace()
    |> Enum.join(separator)
  end

  def split_lines(value, opts \\ [])

  def split_lines(value, opts) when is_binary(value) do
    trim = Keyword.get(opts, :trim, false)

    value
    |> String.split("\n", trim: false)
    |> Enum.map(&String.trim_trailing(&1, "\r"))
    |> maybe_trim_empty_lines(trim)
  end

  def split_lines(_value, _opts), do: []

  def split_blocks_on_blank_lines(value) when is_binary(value) do
    value
    |> split_lines()
    |> Enum.reduce({[], []}, fn line, {blocks, current} ->
      if String.trim(line) == "" do
        flush_block(blocks, current)
      else
        {blocks, current ++ [line]}
      end
    end)
    |> then(fn {blocks, current} -> flush_block(blocks, current) end)
    |> elem(0)
  end

  def split_blocks_on_blank_lines(_value), do: []

  def windows_path_fragment?(value) when is_binary(value), do: scan_windows_path(value)
  def windows_path_fragment?(_value), do: false

  def collapse_slashes(value) when is_binary(value), do: do_collapse_slashes(value, [])
  def collapse_slashes(value), do: value

  def ascii_identifier(value, replacement \\ "_") do
    value
    |> to_string()
    |> String.trim()
    |> scan_ascii_identifier(replacement, [])
  end

  def slugify(value) do
    value
    |> to_string()
    |> String.trim()
    |> String.downcase()
    |> scan_slug([], false)
    |> String.trim("-")
  end

  def kebab_case?(value) when is_binary(value) do
    value != "" and scan_kebab(value, :segment_start)
  end

  def kebab_case?(_value), do: false

  def humanize_separated(value) when is_binary(value) do
    value
    |> split_on_separators()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  def humanize_separated(value), do: value |> to_string() |> humanize_separated()

  def extract_prefixed_ascii_token(value, prefix, allowed_fun)
      when is_binary(value) and is_binary(prefix) and is_function(allowed_fun, 1) do
    case :binary.match(value, prefix) do
      :nomatch ->
        nil

      {start, prefix_size} ->
        tail_start = start + prefix_size
        tail = binary_part(value, tail_start, byte_size(value) - tail_start)
        suffix = take_while(tail, allowed_fun, [])

        if suffix == "" do
          nil
        else
          prefix <> suffix
        end
    end
  end

  def extract_prefixed_ascii_token(_value, _prefix, _allowed_fun), do: nil

  def contains_ci?(value, needle) when is_binary(value) and is_binary(needle) do
    value
    |> String.downcase()
    |> String.contains?(String.downcase(needle))
  end

  def contains_ci?(_value, _needle), do: false

  def hex_lower?(value) when is_binary(value) and byte_size(value) > 0 do
    do_all_bytes?(value, fn byte -> byte in ?0..?9 or byte in ?a..?f end)
  end

  def hex_lower?(_value), do: false

  def base64url?(value) when is_binary(value) and byte_size(value) > 0 do
    do_all_bytes?(value, fn byte ->
      byte in ?A..?Z or byte in ?a..?z or byte in ?0..?9 or byte in [?_, ?-]
    end)
  end

  def base64url?(_value), do: false

  def alnum?(byte), do: byte in ?A..?Z or byte in ?a..?z or byte in ?0..?9

  def ascii_alnum_underscore?(byte), do: alnum?(byte) or byte == ?_

  def ascii_alnum_dot_tilde_dash_underscore?(byte) do
    alnum?(byte) or byte in [?., ?_, ?~, ?-]
  end

  defp maybe_trim_empty_lines(lines, true), do: Enum.reject(lines, &(&1 == ""))
  defp maybe_trim_empty_lines(lines, _), do: lines

  defp flush_block(blocks, []), do: {blocks, []}
  defp flush_block(blocks, current), do: {blocks ++ [Enum.join(current, "\n")], []}

  defp scan_windows_path(<<drive, ?:, slash, _rest::binary>>)
       when (drive in ?A..?Z or drive in ?a..?z) and slash in [?\\, ?/],
       do: true

  defp scan_windows_path(<<_byte, rest::binary>>), do: scan_windows_path(rest)
  defp scan_windows_path(<<>>), do: false

  defp do_collapse_slashes(<<"/", rest::binary>>, ["/" | _] = acc),
    do: do_collapse_slashes(rest, acc)

  defp do_collapse_slashes(<<byte, rest::binary>>, acc),
    do: do_collapse_slashes(rest, [<<byte>> | acc])

  defp do_collapse_slashes(<<>>, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp scan_ascii_identifier(<<byte, rest::binary>>, replacement, acc)
       when byte in ?A..?Z or byte in ?a..?z or byte in ?0..?9 or byte == ?_ do
    scan_ascii_identifier(rest, replacement, [<<byte>> | acc])
  end

  defp scan_ascii_identifier(<<byte, rest::binary>>, replacement, acc)
       when byte in [?\s, ?\t, ?\n, ?\r, ?\v, ?\f] do
    scan_ascii_identifier(rest, replacement, put_replacement(acc, replacement))
  end

  defp scan_ascii_identifier(<<_byte, rest::binary>>, replacement, acc) do
    scan_ascii_identifier(rest, replacement, [replacement | acc])
  end

  defp scan_ascii_identifier(<<>>, _replacement, acc) do
    acc |> Enum.reverse() |> IO.iodata_to_binary()
  end

  defp put_replacement([replacement | _] = acc, replacement), do: acc
  defp put_replacement(acc, replacement), do: [replacement | acc]

  defp scan_slug(<<byte, rest::binary>>, acc, _previous_separator)
       when byte in ?a..?z or byte in ?0..?9 do
    scan_slug(rest, [<<byte>> | acc], false)
  end

  defp scan_slug(<<_byte, rest::binary>>, acc, true), do: scan_slug(rest, acc, true)

  defp scan_slug(<<_byte, rest::binary>>, acc, false),
    do: scan_slug(rest, ["-" | acc], true)

  defp scan_slug(<<>>, acc, _previous_separator),
    do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp scan_kebab(<<byte, rest::binary>>, :segment_start)
       when byte in ?a..?z or byte in ?0..?9,
       do: scan_kebab(rest, :segment)

  defp scan_kebab(<<"-", rest::binary>>, :segment), do: scan_kebab(rest, :segment_start)

  defp scan_kebab(<<byte, rest::binary>>, :segment)
       when byte in ?a..?z or byte in ?0..?9,
       do: scan_kebab(rest, :segment)

  defp scan_kebab(<<>>, :segment), do: true
  defp scan_kebab(_, _), do: false

  defp split_on_separators(value) do
    value
    |> String.split(["-", "_"], trim: true)
    |> Enum.reject(&(&1 == ""))
  end

  defp take_while(<<byte, rest::binary>>, allowed_fun, acc) do
    if allowed_fun.(byte) do
      take_while(rest, allowed_fun, [<<byte>> | acc])
    else
      acc |> Enum.reverse() |> IO.iodata_to_binary()
    end
  end

  defp take_while(<<>>, _allowed_fun, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp do_all_bytes?(<<byte, rest::binary>>, fun) do
    fun.(byte) and do_all_bytes?(rest, fun)
  end

  defp do_all_bytes?(<<>>, _fun), do: true
end
