defmodule Codex.Transport.ExecJsonl do
  @moduledoc false

  @behaviour Codex.Transport

  alias Codex.Thread
  alias Codex.Transport.Support

  @impl true
  def run_turn(%Thread{} = thread, input, turn_opts) when is_binary(input) do
    turn_opts = Support.normalize_turn_opts(turn_opts)

    Support.with_retry_and_rate_limit(
      fn -> Thread.run_turn_exec_jsonl(thread, input, turn_opts) end,
      thread.thread_opts,
      turn_opts
    )
  end

  def run_turn(%Thread{}, _input, _turn_opts), do: {:error, {:unsupported_input, :exec}}

  @impl true
  def run_turn_streamed(%Thread{} = thread, input, turn_opts) when is_binary(input) do
    turn_opts = Support.normalize_turn_opts(turn_opts)

    Support.with_retry_and_rate_limit(
      fn -> Thread.run_turn_streamed_exec_jsonl(thread, input, turn_opts) end,
      thread.thread_opts,
      turn_opts
    )
  end

  def run_turn_streamed(%Thread{}, _input, _turn_opts),
    do: {:error, {:unsupported_input, :exec}}
end
