defmodule Codex.ToolOutput do
  @moduledoc """
  Structured tool output helpers that mirror the Responses input payload shapes.

  Tool implementations may return these structs (or lists thereof). They will be converted
  into codex-compatible maps before being forwarded back to the runner.
  """

  defmodule Text do
    @enforce_keys [:text]
    defstruct [:text]

    @type t :: %__MODULE__{text: String.t()}
  end

  defmodule Image do
    @enforce_keys []
    defstruct [:url, :detail, :file_id, :data]

    @type t :: %__MODULE__{
            url: String.t(),
            detail: String.t() | nil,
            file_id: String.t() | nil,
            data: String.t() | nil
          }
  end

  defmodule FileContent do
    @enforce_keys []
    defstruct [:file_id, :data, :url, :filename, :mime_type]

    @type t :: %__MODULE__{
            file_id: String.t() | nil,
            data: String.t() | nil,
            url: String.t() | nil,
            filename: String.t() | nil,
            mime_type: String.t() | nil
          }
  end

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
  def image(attrs) when is_map(attrs), do: struct!(Image, normalize_keys(attrs))
  def image(attrs) when is_list(attrs), do: attrs |> Map.new() |> image()

  @doc """
  Convenience constructor for file content tool outputs.
  """
  @spec file(keyword() | map()) :: FileContent.t()
  def file(attrs) when is_map(attrs), do: struct!(FileContent, normalize_keys(attrs))
  def file(attrs) when is_list(attrs), do: attrs |> Map.new() |> file()

  @doc """
  Normalizes structured tool outputs into codex-compatible maps.

  Lists are flattened recursively to support tools that emit multiple items.
  """
  @spec normalize(t()) :: list() | map()
  def normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  def normalize(%Text{text: text}), do: %{"type" => "input_text", "text" => text}

  def normalize(%Image{} = image) do
    base =
      %{}
      |> maybe_put("url", image.url)
      |> maybe_put("detail", image.detail || "auto")
      |> maybe_put("file_id", image.file_id)
      |> maybe_put("data", image.data)

    %{"type" => "input_image", "image_url" => base}
  end

  def normalize(%FileContent{} = file) do
    file_data =
      %{}
      |> maybe_put("file_id", file.file_id)
      |> maybe_put("data", file.data)
      |> maybe_put("url", file.url)
      |> maybe_put("filename", file.filename)
      |> maybe_put("mime_type", file.mime_type)

    %{"type" => "input_file", "file_data" => file_data}
  end

  def normalize(%_struct{} = struct), do: struct |> Map.from_struct() |> normalize()
  def normalize(%{} = map), do: stringify_keys(map)
  def normalize(other), do: other

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

  defp normalize_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      normalized_key =
        case key do
          k when is_atom(k) -> k
          k when is_binary(k) -> String.to_atom(k)
          other -> other
        end

      {normalized_key, value}
    end)
  end
end
