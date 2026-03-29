defmodule CodexExamples.Support do
  @moduledoc false

  alias Codex.ExamplesSupport

  def init!(argv \\ System.argv()), do: ExamplesSupport.init_example!(argv)
  def ssh_enabled?, do: ExamplesSupport.ssh_enabled?()
  def execution_surface, do: ExamplesSupport.execution_surface()
  def command_opts(opts \\ []), do: ExamplesSupport.command_opts(opts)
  def codex_options!(attrs \\ %{}, opts \\ []), do: ExamplesSupport.codex_options!(attrs, opts)
  def codex_options(attrs \\ %{}, opts \\ []), do: ExamplesSupport.codex_options(attrs, opts)

  def ensure_auth_available(message \\ nil),
    do:
      ExamplesSupport.ensure_auth_available(
        message ||
          "authenticate with `codex login` or set CODEX_API_KEY before running this example"
      )

  def ensure_app_server_supported(codex_opts),
    do: ExamplesSupport.ensure_app_server_supported(codex_opts)
end
