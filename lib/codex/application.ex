defmodule Codex.Application do
  @moduledoc false
  use Application

  require Logger

  alias Codex.Telemetry

  @impl true
  def start(_type, _args) do
    maybe_print_otlp_banner()
    Telemetry.configure()

    children = [
      {Codex.AppServer.Supervisor, []},
      {Codex.Files.Registry, []},
      {Codex.Approvals.Registry, []},
      {Codex.Tools.MetricsHeir, []},
      {Task.Supervisor, name: Codex.TaskSupervisor}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Codex.Supervisor)
  end

  defp maybe_print_otlp_banner do
    case Telemetry.otlp_enabled?() do
      true ->
        Logger.info("OTLP telemetry enabled (set CODEX_OTLP_ENABLE=0 to disable)")

      false ->
        Logger.info("OTLP telemetry disabled (set CODEX_OTLP_ENABLE=1 to enable)")
    end
  end
end
