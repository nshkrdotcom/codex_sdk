defmodule Codex.OAuth.PKCE do
  @moduledoc false

  @enforce_keys [:verifier, :challenge, :method]
  defstruct [:verifier, :challenge, :method]

  @type t :: %__MODULE__{
          verifier: String.t(),
          challenge: String.t(),
          method: String.t()
        }

  @verifier_bytes 48
  @challenge_method "S256"

  @spec generate() :: t()
  def generate do
    verifier = generate_verifier()

    %__MODULE__{
      verifier: verifier,
      challenge: challenge(verifier),
      method: @challenge_method
    }
  end

  @spec generate_verifier() :: String.t()
  def generate_verifier do
    @verifier_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  @spec challenge(String.t()) :: String.t()
  def challenge(verifier) when is_binary(verifier) do
    verifier
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
  end
end
