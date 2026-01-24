defmodule Codex.Protocol.TextElement do
  @moduledoc """
  Text element with byte range for rich text input.

  Used to preserve UI element metadata in user input text.
  """

  use TypedStruct
  alias Codex.Protocol.ByteRange

  typedstruct do
    @typedoc "A text element with byte range and optional placeholder"
    field(:byte_range, ByteRange.t(), enforce: true)
    field(:placeholder, String.t() | nil)
  end

  @spec from_map(map()) :: t()
  def from_map(%{"byte_range" => byte_range} = data) do
    %__MODULE__{
      byte_range: ByteRange.from_map(byte_range),
      placeholder: Map.get(data, "placeholder")
    }
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = te) do
    %{"byte_range" => ByteRange.to_map(te.byte_range)}
    |> maybe_put("placeholder", te.placeholder)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end

defmodule Codex.Protocol.ByteRange do
  @moduledoc """
  Byte range for text element positioning.
  """

  use TypedStruct

  typedstruct do
    @typedoc "A byte range with start and end positions"
    field(:start, non_neg_integer(), enforce: true)
    field(:end, non_neg_integer(), enforce: true)
  end

  @spec from_map(map()) :: t()
  def from_map(%{"start" => start, "end" => end_pos}) do
    %__MODULE__{start: start, end: end_pos}
  end

  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = br) do
    %{"start" => br.start, "end" => br.end}
  end
end
