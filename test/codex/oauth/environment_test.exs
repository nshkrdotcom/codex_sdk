defmodule Codex.OAuth.EnvironmentTest do
  use ExUnit.Case, async: true

  alias Codex.OAuth.Environment

  test "macOS desktop defaults to browser flow" do
    environment =
      Environment.detect(
        os: :macos,
        env: %{"TERM" => "xterm-256color"},
        interactive?: true
      )

    assert environment.os == :macos
    assert environment.preferred_flow == :browser_code
    assert environment.fallback_flow == nil
    refute environment.headless?
    refute environment.wsl?
  end

  test "linux desktop defaults to browser flow" do
    environment =
      Environment.detect(
        os: :linux,
        env: %{"DISPLAY" => ":0", "TERM" => "xterm-256color"},
        interactive?: true
      )

    assert environment.os == :linux
    assert environment.preferred_flow == :browser_code
    refute environment.headless?
  end

  test "windows native defaults to browser flow" do
    environment =
      Environment.detect(
        os: :windows,
        env: %{"TERM" => "xterm-256color"},
        interactive?: true
      )

    assert environment.os == :windows
    assert environment.preferred_flow == :browser_code
    refute environment.wsl?
  end

  test "wsl prefers browser flow with device fallback" do
    environment =
      Environment.detect(
        os: :linux,
        env: %{"WSL_DISTRO_NAME" => "Ubuntu", "TERM" => "xterm-256color"},
        interactive?: true
      )

    assert environment.wsl?
    assert environment.preferred_flow == :browser_code
    assert environment.fallback_flow == :device_code
  end

  test "ssh headless sessions default to device flow" do
    environment =
      Environment.detect(
        os: :linux,
        env: %{"SSH_CONNECTION" => "1 2 3 4"},
        interactive?: true
      )

    assert environment.ssh?
    assert environment.headless?
    assert environment.preferred_flow == :device_code
  end

  test "containers default to device flow" do
    environment =
      Environment.detect(
        os: :linux,
        env: %{"container" => "docker", "TERM" => "xterm-256color"},
        interactive?: true
      )

    assert environment.container?
    assert environment.preferred_flow == :device_code
  end

  test "ci disables interactive login" do
    environment =
      Environment.detect(
        os: :linux,
        env: %{"CI" => "true", "TERM" => "xterm-256color"},
        interactive?: true
      )

    assert environment.ci?
    refute environment.interactive?
    assert environment.preferred_flow == :none
  end
end
