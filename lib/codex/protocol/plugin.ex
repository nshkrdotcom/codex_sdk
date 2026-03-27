defmodule Codex.Protocol.Plugin do
  @moduledoc """
  Typed app-server plugin request and response models.

  Raw plugin wrappers remain available on `Codex.AppServer` for callers that
  want the original map payloads. The typed surface adds schema-backed params,
  typed responses, and `Codex.AppServer.request_typed/5`.
  """
end
