defmodule Codex.OAuth.Environment do
  @moduledoc false

  @enforce_keys [
    :os,
    :wsl?,
    :ssh?,
    :container?,
    :ci?,
    :headless?,
    :interactive?,
    :preferred_flow,
    :fallback_flow
  ]
  defstruct [
    :os,
    :wsl?,
    :ssh?,
    :container?,
    :ci?,
    :headless?,
    :interactive?,
    :preferred_flow,
    :fallback_flow
  ]

  @type flow :: :browser_code | :device_code | :none

  @type t :: %__MODULE__{
          os: :macos | :linux | :windows | :unknown,
          wsl?: boolean(),
          ssh?: boolean(),
          container?: boolean(),
          ci?: boolean(),
          headless?: boolean(),
          interactive?: boolean(),
          preferred_flow: flow(),
          fallback_flow: flow() | nil
        }

  @spec detect(keyword()) :: t()
  def detect(opts \\ []) when is_list(opts) do
    env = normalize_env(Keyword.get(opts, :env, System.get_env()))
    os = Keyword.get(opts, :os) || detect_os()
    wsl? = truthy_override(Keyword.get(opts, :wsl?), wsl?(os, env))
    ssh? = truthy_override(Keyword.get(opts, :ssh?), ssh?(env))
    container? = truthy_override(Keyword.get(opts, :container?), container?(env))
    ci? = truthy_override(Keyword.get(opts, :ci?), ci?(env))
    interactive? = truthy_override(Keyword.get(opts, :interactive?), interactive?(env, ci?))
    headless? = truthy_override(Keyword.get(opts, :headless?), headless?(os, env, ssh?, wsl?))

    {preferred_flow, fallback_flow} =
      choose_flow(os, interactive?, wsl?, ssh?, container?, headless?)

    %__MODULE__{
      os: os,
      wsl?: wsl?,
      ssh?: ssh?,
      container?: container?,
      ci?: ci?,
      headless?: headless?,
      interactive?: interactive? and not ci?,
      preferred_flow: if(ci?, do: :none, else: preferred_flow),
      fallback_flow: if(ci?, do: nil, else: fallback_flow)
    }
  end

  defp choose_flow(_os, false, _wsl?, _ssh?, _container?, _headless?), do: {:none, nil}

  defp choose_flow(_os, _interactive?, _wsl?, true, _container?, _headless?),
    do: {:device_code, nil}

  defp choose_flow(_os, _interactive?, _wsl?, _ssh?, true, _headless?), do: {:device_code, nil}

  defp choose_flow(_os, _interactive?, true, _ssh?, _container?, _headless?),
    do: {:browser_code, :device_code}

  defp choose_flow(:macos, _interactive?, _wsl?, _ssh?, _container?, _headless?),
    do: {:browser_code, nil}

  defp choose_flow(:windows, _interactive?, _wsl?, _ssh?, _container?, _headless?),
    do: {:browser_code, nil}

  defp choose_flow(:linux, _interactive?, _wsl?, _ssh?, _container?, false),
    do: {:browser_code, nil}

  defp choose_flow(:linux, _interactive?, _wsl?, _ssh?, _container?, true),
    do: {:device_code, nil}

  defp choose_flow(_os, _interactive?, _wsl?, _ssh?, _container?, _headless?),
    do: {:device_code, nil}

  defp detect_os do
    case :os.type() do
      {:unix, :darwin} -> :macos
      {:unix, :linux} -> :linux
      {:win32, _} -> :windows
      _ -> :unknown
    end
  end

  defp wsl?(:linux, env) do
    truthy?(Map.get(env, "WSL_DISTRO_NAME")) or truthy?(Map.get(env, "WSL_INTEROP"))
  end

  defp wsl?(_os, _env), do: false

  defp ssh?(env) do
    truthy?(Map.get(env, "SSH_CONNECTION")) or truthy?(Map.get(env, "SSH_CLIENT")) or
      truthy?(Map.get(env, "SSH_TTY"))
  end

  defp container?(env) do
    truthy?(Map.get(env, "container")) or truthy?(Map.get(env, "KUBERNETES_SERVICE_HOST"))
  end

  defp ci?(env) do
    truthy?(Map.get(env, "CI")) or truthy?(Map.get(env, "GITHUB_ACTIONS")) or
      truthy?(Map.get(env, "BUILDKITE"))
  end

  defp interactive?(env, ci?) do
    cond do
      ci? -> false
      Map.get(env, "TERM") in [nil, "", "dumb"] -> false
      true -> true
    end
  end

  defp headless?(:linux, env, ssh?, wsl?) do
    ssh? or
      (!wsl? and !truthy?(Map.get(env, "DISPLAY")) and !truthy?(Map.get(env, "WAYLAND_DISPLAY")))
  end

  defp headless?(_os, _env, ssh?, _wsl?), do: ssh?

  defp normalize_env(env) when is_map(env), do: env

  defp normalize_env(env) when is_list(env),
    do: Map.new(env, fn {key, value} -> {to_string(key), value} end)

  defp normalize_env(_), do: %{}

  defp truthy_override(nil, default), do: default
  defp truthy_override(value, _default), do: value

  defp truthy?(value) when is_binary(value), do: String.trim(value) != ""
  defp truthy?(value), do: not is_nil(value) and value != false
end
