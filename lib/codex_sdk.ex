defmodule CodexSdk do
  @moduledoc """
  Backwards-compatible entry module for the Codex SDK.

  Prefer using the `Codex` module directly.
  """

  defdelegate start_thread(opts \\ %{}, thread_opts \\ %{}), to: Codex
  defdelegate resume_thread(thread_id, opts \\ %{}, thread_opts \\ %{}), to: Codex
end
