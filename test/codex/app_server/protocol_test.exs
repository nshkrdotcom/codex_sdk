defmodule Codex.AppServer.ProtocolTest do
  use ExUnit.Case, async: true

  alias Codex.AppServer.Protocol

  describe "decode_lines/2" do
    test "buffers partial lines across chunks" do
      chunk1 = ~s({"id":1,"method":"initialize"}\n{"id":2)
      {messages1, buffer1, non_json1} = Protocol.decode_lines("", chunk1)

      assert non_json1 == []
      assert buffer1 == ~s({"id":2)
      assert messages1 == [%{"id" => 1, "method" => "initialize"}]

      {messages2, buffer2, non_json2} = Protocol.decode_lines(buffer1, ~s(,"result":{}}\n))

      assert non_json2 == []
      assert buffer2 == ""
      assert messages2 == [%{"id" => 2, "result" => %{}}]
    end

    test "decodes multiple lines from a single chunk" do
      chunk = ~s({"id":1,"result":{}}\n{"method":"turn/started","params":{}}\n)

      assert {messages, "", []} = Protocol.decode_lines("", chunk)

      assert messages == [
               %{"id" => 1, "result" => %{}},
               %{"method" => "turn/started", "params" => %{}}
             ]
    end

    test "returns non-JSON lines separately and continues" do
      import ExUnit.CaptureLog

      chunk = "not-json\n" <> ~s({"id":1,"result":{}}\n)

      log =
        capture_log(fn ->
          assert {[%{"id" => 1, "result" => %{}}], "", ["not-json"]} =
                   Protocol.decode_lines("", chunk)
        end)

      assert log =~ "Failed to decode JSON line"
      assert log =~ "not-json"
    end
  end

  describe "message_type/1" do
    test "classifies requests, notifications, responses, and errors" do
      assert Protocol.message_type(%{"id" => 1, "method" => "thread/start"}) == :request
      assert Protocol.message_type(%{"method" => "turn/started"}) == :notification
      assert Protocol.message_type(%{"id" => 1, "result" => %{}}) == :response

      assert Protocol.message_type(%{
               "id" => "abc",
               "error" => %{"code" => -32_000, "message" => "boom"}
             }) == :error
    end
  end
end
