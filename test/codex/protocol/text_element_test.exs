defmodule Codex.Protocol.TextElementTest do
  use ExUnit.Case, async: true

  alias Codex.Protocol.{ByteRange, TextElement}

  test "from_map/1 parses byte range and placeholder" do
    data = %{"byte_range" => %{"start" => 1, "end" => 3}, "placeholder" => "img"}

    assert %TextElement{byte_range: %ByteRange{start: 1, end: 3}, placeholder: "img"} =
             TextElement.from_map(data)
  end

  test "to_map/1 omits nil placeholder" do
    element = %TextElement{byte_range: %ByteRange{start: 0, end: 4}, placeholder: nil}

    assert %{"byte_range" => %{"start" => 0, "end" => 4}} = TextElement.to_map(element)
  end

  test "byte range round-trips" do
    range = %ByteRange{start: 2, end: 5}
    assert %{"start" => 2, "end" => 5} = ByteRange.to_map(range)
    assert %ByteRange{start: 2, end: 5} = ByteRange.from_map(%{"start" => 2, "end" => 5})
  end
end
