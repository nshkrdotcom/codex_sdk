defmodule Codex.Protocol.ConfigTypesTest do
  use ExUnit.Case, async: true

  alias Codex.Protocol.ConfigTypes

  test "web search mode encoding and decoding" do
    assert "disabled" == ConfigTypes.encode_web_search_mode(:disabled)
    assert "cached" == ConfigTypes.encode_web_search_mode(:cached)
    assert "live" == ConfigTypes.encode_web_search_mode(:live)

    assert :disabled == ConfigTypes.decode_web_search_mode(nil)
    assert :disabled == ConfigTypes.decode_web_search_mode("disabled")
    assert :cached == ConfigTypes.decode_web_search_mode("cached")
    assert :live == ConfigTypes.decode_web_search_mode("live")
  end

  test "personality encoding and decoding" do
    assert "friendly" == ConfigTypes.encode_personality(:friendly)
    assert "pragmatic" == ConfigTypes.encode_personality(:pragmatic)

    assert nil == ConfigTypes.decode_personality(nil)
    assert :friendly == ConfigTypes.decode_personality("friendly")
    assert :pragmatic == ConfigTypes.decode_personality("pragmatic")
  end

  test "trust level encoding and decoding" do
    assert "trusted" == ConfigTypes.encode_trust_level(:trusted)
    assert "untrusted" == ConfigTypes.encode_trust_level(:untrusted)

    assert nil == ConfigTypes.decode_trust_level(nil)
    assert :trusted == ConfigTypes.decode_trust_level("trusted")
    assert :untrusted == ConfigTypes.decode_trust_level("untrusted")
  end
end
