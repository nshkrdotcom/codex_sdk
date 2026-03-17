defmodule Codex.OAuth.PKCETest do
  use ExUnit.Case, async: true

  alias Codex.OAuth.PKCE
  alias Codex.OAuth.State

  test "generate_verifier/0 returns a URL-safe high-entropy verifier" do
    verifier = PKCE.generate_verifier()

    assert byte_size(verifier) >= 43
    assert verifier =~ ~r/^[A-Za-z0-9._~-]+$/
  end

  test "challenge/1 implements RFC 7636 S256" do
    verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

    assert PKCE.challenge(verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
  end

  test "generate/0 always uses S256" do
    pkce = PKCE.generate()

    assert pkce.method == "S256"
    assert pkce.challenge == PKCE.challenge(pkce.verifier)
  end

  test "state.generate/0 returns a URL-safe per-attempt value" do
    state1 = State.generate()
    state2 = State.generate()

    assert byte_size(state1) >= 32
    assert state1 =~ ~r/^[A-Za-z0-9_-]+$/
    assert state1 != state2
  end
end
