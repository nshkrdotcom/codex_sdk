defmodule Codex.Schema do
  @moduledoc false

  alias CliSubprocessCore.Schema, as: CoreSchema

  defdelegate parse(schema, value, tag), to: CoreSchema
  defdelegate parse!(schema, value, tag), to: CoreSchema
  defdelegate split_extra(map, keys), to: CoreSchema
  defdelegate merge_extra(projected, extra), to: CoreSchema
  defdelegate to_map(struct, keys), to: CoreSchema
end
