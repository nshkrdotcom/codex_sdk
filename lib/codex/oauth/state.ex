defmodule Codex.OAuth.State do
  @moduledoc false

  @bytes 32

  @spec generate() :: String.t()
  def generate do
    @bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end
end
