defmodule Codex.Runtime.KeyringWarning do
  @moduledoc """
  Deduplicated warn-once logic for keyring-related warnings.
  """

  require Logger

  @spec warn_once(term(), String.t()) :: :ok
  def warn_once(key, message) when is_binary(message) do
    case :persistent_term.get(key, false) do
      true ->
        :ok

      false ->
        Logger.warning(message)
        :persistent_term.put(key, true)
    end
  end
end
