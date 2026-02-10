defmodule Codex.IO.BufferTest do
  use ExUnit.Case, async: true

  alias Codex.IO.Buffer

  describe "split_lines/1" do
    test "splits complete lines" do
      assert {["hello", "world"], ""} = Buffer.split_lines("hello\nworld\n")
    end

    test "preserves trailing fragment" do
      assert {["hello"], "wor"} = Buffer.split_lines("hello\nwor")
    end

    test "returns empty lines and full fragment for no newline" do
      assert {[], "hello"} = Buffer.split_lines("hello")
    end

    test "handles empty input" do
      assert {[], ""} = Buffer.split_lines("")
    end

    test "handles multi-chunk accumulation" do
      {lines1, rest1} = Buffer.split_lines("hel")
      assert {[], "hel"} = {lines1, rest1}

      {lines2, rest2} = Buffer.split_lines(rest1 <> "lo\nwor")
      assert {["hello"], "wor"} = {lines2, rest2}

      {lines3, rest3} = Buffer.split_lines(rest2 <> "ld\n")
      assert {["world"], ""} = {lines3, rest3}
    end

    test "handles consecutive newlines" do
      assert {["hello", "", "world"], ""} = Buffer.split_lines("hello\n\nworld\n")
    end
  end

  describe "decode_json_lines/2" do
    test "decodes complete JSON lines and preserves buffer" do
      {decoded, rest, non_json} = Buffer.decode_json_lines("", "{\"a\":1}\n{\"b\":2}\npartial")
      assert [%{"a" => 1}, %{"b" => 2}] = decoded
      assert rest == "partial"
      assert non_json == []
    end

    test "accumulates with existing buffer" do
      {decoded, rest, non_json} = Buffer.decode_json_lines("{\"he\":\"wor", "ld\"}\n")
      assert [%{"he" => "world"}] = decoded
      assert rest == ""
      assert non_json == []
    end

    test "returns non-JSON lines separately" do
      {decoded, rest, non_json} = Buffer.decode_json_lines("", "not json\n{\"a\":1}\n")
      assert [%{"a" => 1}] = decoded
      assert rest == ""
      assert non_json == ["not json"]
    end

    test "handles empty chunk" do
      {decoded, rest, non_json} = Buffer.decode_json_lines("buf", "")
      assert [] = decoded
      assert rest == "buf"
      assert non_json == []
    end
  end

  describe "decode_complete_lines/1" do
    test "decodes a list of JSON strings" do
      {decoded, non_json} = Buffer.decode_complete_lines(["{\"a\":1}", "{\"b\":2}"])
      assert [%{"a" => 1}, %{"b" => 2}] = decoded
      assert non_json == []
    end

    test "returns non-JSON lines separately" do
      assert {[], ["hello"]} = Buffer.decode_complete_lines(["hello"])
    end

    test "skips empty lines" do
      assert {[%{"a" => 1}], []} = Buffer.decode_complete_lines(["", "{\"a\":1}", ""])
    end
  end

  describe "decode_line/1" do
    test "decodes valid JSON object" do
      assert {:ok, %{"key" => "val"}} = Buffer.decode_line("{\"key\":\"val\"}")
    end

    test "returns non_json for arrays" do
      assert {:non_json, "[1,2]"} = Buffer.decode_line("[1,2]")
    end

    test "returns non_json for invalid JSON" do
      assert {:non_json, "not json"} = Buffer.decode_line("not json")
    end

    test "returns non_json for empty string" do
      assert {:non_json, ""} = Buffer.decode_line("")
    end
  end

  describe "iodata_to_binary/1" do
    test "converts iolist to binary" do
      assert "hello" = Buffer.iodata_to_binary(["he", "llo"])
    end

    test "passes through binary unchanged" do
      assert "hello" = Buffer.iodata_to_binary("hello")
    end
  end
end
