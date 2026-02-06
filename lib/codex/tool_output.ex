defmodule Codex.ToolOutput do
  @moduledoc """
  Structured tool output helpers that mirror the Responses input payload shapes.

  Tool implementations may return these structs (or lists thereof). They will be converted
  into codex-compatible maps before being forwarded back to the runner.
  """

  defmodule Text do
    @moduledoc """
    Text tool output.

    Normalizes to an `input_text` map via `Codex.ToolOutput.normalize/1`.
    """

    @enforce_keys [:text]
    defstruct [:text]

    @typedoc "Text tool output."
    @type t :: %__MODULE__{text: String.t()}
  end

  defmodule Image do
    @moduledoc """
    Image tool output.

    Normalizes to an `input_image` map via `Codex.ToolOutput.normalize/1`.
    """

    @enforce_keys []
    defstruct [:url, :detail, :file_id, :data]

    @typedoc "Image tool output."
    @type t :: %__MODULE__{
            url: String.t(),
            detail: String.t() | nil,
            file_id: String.t() | nil,
            data: String.t() | nil
          }
  end

  defmodule FileContent do
    @moduledoc """
    File content tool output.

    Normalizes to an `input_file` map via `Codex.ToolOutput.normalize/1`.
    """

    @enforce_keys []
    defstruct [:file_id, :data, :url, :filename, :mime_type]

    @typedoc "File content tool output."
    @type t :: %__MODULE__{
            file_id: String.t() | nil,
            data: String.t() | nil,
            url: String.t() | nil,
            filename: String.t() | nil,
            mime_type: String.t() | nil
          }
  end

  @image_key_map %{
    "url" => :url,
    "detail" => :detail,
    "file_id" => :file_id,
    "data" => :data
  }

  @file_key_map %{
    "file_id" => :file_id,
    "data" => :data,
    "url" => :url,
    "filename" => :filename,
    "mime_type" => :mime_type
  }

  @type t :: Text.t() | Image.t() | FileContent.t() | map() | list()

  @doc """
  Convenience constructor for text tool outputs.
  """
  @spec text(String.t()) :: Text.t()
  def text(text) when is_binary(text), do: %Text{text: text}

  @doc """
  Convenience constructor for image tool outputs.
  """
  @spec image(keyword() | map()) :: Image.t()
  def image(attrs) when is_map(attrs), do: struct!(Image, normalize_keys(attrs, @image_key_map))
  def image(attrs) when is_list(attrs), do: attrs |> Map.new() |> image()

  @doc """
  Convenience constructor for file content tool outputs.
  """
  @spec file(keyword() | map()) :: FileContent.t()
  def file(attrs) when is_map(attrs),
    do: struct!(FileContent, normalize_keys(attrs, @file_key_map))

  def file(attrs) when is_list(attrs), do: attrs |> Map.new() |> file()

  @doc """
  Normalizes structured tool outputs into codex-compatible maps.

  Lists are flattened and deduplicated to mirror the Python runner's history
  merging semantics.
  """
  @spec normalize(t()) :: list() | map()
  def normalize(list) when is_list(list) do
    list
    |> List.flatten()
    |> Enum.map(&normalize_single/1)
    |> List.flatten()
    |> dedup_outputs()
  end

  def normalize(value), do: normalize_single(value)

  defp normalize_single(%Text{text: text}), do: %{"type" => "input_text", "text" => text}

  defp normalize_single(%Image{} = image) do
    base =
      %{}
      |> maybe_put("url", image.url)
      |> maybe_put("detail", image.detail || "auto")
      |> maybe_put("file_id", image.file_id)
      |> maybe_put("data", image.data)

    %{"type" => "input_image", "image_url" => base}
  end

  defp normalize_single(%FileContent{} = file) do
    file_data =
      %{}
      |> maybe_put("file_id", file.file_id)
      |> maybe_put("data", file.data)
      |> maybe_put("file_url", file.url)
      |> maybe_put("filename", file.filename)
      |> maybe_put("mime_type", file.mime_type)

    %{"type" => "input_file", "file_data" => file_data}
  end

  defp normalize_single(%Codex.Files.Attachment{} = attachment) do
    %{
      "type" => "input_file",
      "file_data" => attachment_file_data(attachment)
    }
  end

  defp normalize_single(%_struct{} = struct),
    do: struct |> Map.from_struct() |> normalize_single()

  defp normalize_single(%{} = map), do: stringify_keys(map)
  defp normalize_single(other), do: other

  defp attachment_file_data(%Codex.Files.Attachment{} = attachment) do
    %{
      "file_id" => attachment.id,
      "filename" => attachment.name,
      "data" => attachment.path |> File.read!() |> Base.encode64()
    }
  end

  defp dedup_outputs(list) do
    list
    |> Enum.reduce({[], MapSet.new()}, fn item, {acc, seen} ->
      key = dedup_key(item)

      if MapSet.member?(seen, key) do
        {acc, seen}
      else
        {[item | acc], MapSet.put(seen, key)}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp dedup_key(%{"type" => "input_image", "image_url" => %{} = image_url}) do
    {:input_image,
     Map.get(image_url, "file_id") || Map.get(image_url, "url") || Map.get(image_url, "data")}
  end

  defp dedup_key(%{"type" => "input_file", "file_data" => %{} = file_data}) do
    {:input_file,
     Map.get(file_data, "file_id") ||
       Map.get(file_data, "file_url") ||
       Map.get(file_data, "data") ||
       Map.get(file_data, "filename")}
  end

  defp dedup_key(other), do: other

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      {stringify_key(key), stringify_value(value)}
    end)
  end

  defp stringify_keys(list) when is_list(list), do: Enum.map(list, &stringify_keys/1)
  defp stringify_keys(other), do: other

  defp stringify_value(value) when is_map(value), do: stringify_keys(value)
  defp stringify_value(value) when is_list(value), do: Enum.map(value, &stringify_value/1)
  defp stringify_value(value), do: value

  defp stringify_key(key) when is_atom(key), do: Atom.to_string(key)
  defp stringify_key(key) when is_binary(key), do: key
  defp stringify_key(key), do: to_string(key)

  defp normalize_keys(map, key_map) when is_map(map) and is_map(key_map) do
    Map.new(map, fn {key, value} ->
      normalized_key = normalize_key(key, key_map)

      {normalized_key, value}
    end)
  end

  defp normalize_key(key, _key_map) when is_atom(key), do: key
  defp normalize_key(key, key_map) when is_binary(key), do: Map.get(key_map, key, key)
  defp normalize_key(other, _key_map), do: other
end
