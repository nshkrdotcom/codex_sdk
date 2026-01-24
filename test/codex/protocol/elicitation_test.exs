defmodule Codex.Protocol.ElicitationTest do
  use ExUnit.Case, async: true

  alias Codex.Protocol.Elicitation

  test "request parsing extracts fields" do
    data = %{"server_name" => "mcp", "id" => "req_1", "message" => "Proceed?"}

    assert %Elicitation.Request{server_name: "mcp", id: "req_1", message: "Proceed?"} =
             Elicitation.Request.from_map(data)
  end

  test "encodes and decodes actions" do
    assert "accept" == Elicitation.encode_action(:accept)
    assert "decline" == Elicitation.encode_action(:decline)
    assert "cancel" == Elicitation.encode_action(:cancel)

    assert :accept == Elicitation.decode_action("accept")
    assert :decline == Elicitation.decode_action("decline")
    assert :cancel == Elicitation.decode_action("cancel")
  end
end
