defmodule Codex.Thread.Backoff do
  @moduledoc false

  import Bitwise

  alias Codex.Config.Defaults

  @base_delay_ms Defaults.backoff_base_delay_ms()
  @max_backoff_ms Defaults.backoff_max_ms()
  @max_exponent Defaults.backoff_max_exponent()

  @spec delay_ms(integer()) :: non_neg_integer()
  def delay_ms(attempt) when is_integer(attempt) and attempt >= 1 do
    exponent = min(attempt - 1, @max_exponent)
    delay = @base_delay_ms * (1 <<< exponent)
    min(delay, @max_backoff_ms)
  end

  def delay_ms(_attempt), do: 0

  @spec sleep(integer()) :: :ok
  def sleep(attempt) do
    delay = delay_ms(attempt)

    if delay > 0 do
      Process.sleep(delay)
    end

    :ok
  end
end
