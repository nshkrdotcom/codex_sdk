defmodule Codex.Transport.SupportTest do
  use ExUnit.Case, async: true

  alias Codex.Error
  alias Codex.Thread.Options, as: ThreadOptions
  alias Codex.Transport.Support

  test "retries when enabled" do
    {:ok, thread_opts} =
      ThreadOptions.new(%{
        retry: true,
        retry_opts: [max_attempts: 2, base_delay_ms: 0, jitter: false]
      })

    counter = :counters.new(1, [])

    fun = fn ->
      :ok = :counters.add(counter, 1, 1)
      attempt = :counters.get(counter, 1)

      if attempt == 1 do
        {:error, {:exec_failed, Error.rate_limit("Rate limited", retry_after_ms: 1)}}
      else
        {:ok, :ok}
      end
    end

    assert {:ok, :ok} = Support.with_retry_and_rate_limit(fun, thread_opts, %{})
    assert :counters.get(counter, 1) == 2
  end
end
