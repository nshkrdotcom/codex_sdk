defmodule CodexExamples.Support do
  @moduledoc false

  alias Codex.ExamplesSupport

  def init!(argv \\ System.argv()), do: ExamplesSupport.init_example!(argv)
  def ssh_enabled?, do: ExamplesSupport.ssh_enabled?()
  def execution_surface, do: ExamplesSupport.execution_surface()
  def command_opts(opts \\ []), do: ExamplesSupport.command_opts(opts)
  def example_working_directory, do: ExamplesSupport.example_working_directory()

  def remote_working_directory_configured?,
    do: ExamplesSupport.remote_working_directory_configured?()

  def ensure_remote_working_directory(message \\ nil),
    do:
      ExamplesSupport.ensure_remote_working_directory(
        message ||
          "this SSH app-server example requires --cwd <remote trusted directory> because app-server thread start does not expose --skip-git-repo-check"
      )

  def ensure_local_execution_surface(message \\ nil),
    do:
      ExamplesSupport.ensure_local_execution_surface(
        message || "this example uses local host resources and does not support --ssh-host"
      )

  def thread_opts!(attrs \\ %{}), do: ExamplesSupport.thread_opts!(attrs)
  def thread_opts(attrs \\ %{}), do: ExamplesSupport.thread_opts(attrs)
  def codex_options!(attrs \\ %{}, opts \\ []), do: ExamplesSupport.codex_options!(attrs, opts)
  def codex_options(attrs \\ %{}, opts \\ []), do: ExamplesSupport.codex_options(attrs, opts)

  def ensure_auth_available(message \\ nil),
    do: ExamplesSupport.ensure_auth_available(message || ExamplesSupport.default_auth_message())

  def ensure_app_server_supported(codex_opts),
    do: ExamplesSupport.ensure_app_server_supported(codex_opts)
end
