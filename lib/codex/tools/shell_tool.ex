defmodule Codex.Tools.ShellTool do
  @moduledoc """
  Hosted tool for executing shell commands.

  ## Overview

  ShellTool provides a fully-featured shell command execution environment with
  approval integration, timeout handling, and output truncation. It can be used
  standalone or registered in the tool registry.

  ## Options

  Options can be passed during registration or via context metadata:

    * `:executor` - Custom executor function (default: built-in shell executor)
    * `:approval` - Approval callback or policy for command review
    * `:max_output_bytes` - Maximum output size before truncation (default: 10,000)
    * `:timeout_ms` - Command timeout in milliseconds (default: 60,000)
    * `:cwd` - Default working directory
    * `:env` - Environment variables map

  ## Usage

  ### Direct Invocation

      args = %{"command" => ["bash", "-lc", "ls -la"], "workdir" => "/tmp"}
      {:ok, result} = Codex.Tools.ShellTool.invoke(args, %{})
      # => %{"output" => "...", "exit_code" => 0, "success" => true}

  ### With Registry

      {:ok, _handle} = Codex.Tools.register(Codex.Tools.ShellTool,
        max_output_bytes: 5000,
        timeout_ms: 30_000,
        approval: fn cmd, _ctx -> :ok end
      )

      {:ok, result} =
        Codex.Tools.invoke("shell", %{"command" => ["bash", "-lc", "echo hello"]}, %{})

  ## Approval Integration

  The approval callback can be:
    * A 2-arity function `fn(command, context) -> :ok | {:deny, reason}`
    * A 3-arity function `fn(command, context, metadata) -> :ok | {:deny, reason}`
    * A module implementing `review_tool/2` callback

  ## Custom Executor

  The executor callback receives `(args, context, metadata)` and should return:
    * `{:ok, output}` - where output is a string or map
    * `{:error, reason}` - on failure

  For testing, provide a mock executor:

      executor = fn %{"command" => cmd}, _ctx, _meta ->
        {:ok, %{"output" => "mocked: \#{cmd}", "exit_code" => 0}}
      end

      {:ok, _} = Codex.Tools.register(Codex.Tools.ShellTool, executor: executor)

  """

  @behaviour Codex.Tool

  alias Codex.Tools.Hosted

  @default_timeout_ms 60_000
  @default_max_output_bytes 10_000

  @impl true
  def metadata do
    %{
      name: "shell",
      description: "Execute shell commands",
      schema: %{
        "type" => "object",
        "properties" => %{
          "command" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "description" => "The command to execute"
          },
          "workdir" => %{
            "type" => "string",
            "description" => "Working directory (optional)"
          },
          "timeout_ms" => %{
            "type" => "integer",
            "description" => "Timeout in milliseconds (optional)"
          },
          "sandbox_permissions" => %{
            "type" => "string",
            "description" =>
              "Sandbox permissions for the command. Set to \"require_escalated\" to request running without sandbox restrictions; defaults to \"use_default\"."
          },
          "justification" => %{
            "type" => "string",
            "description" =>
              "Only set if sandbox_permissions is \"require_escalated\". 1-sentence explanation of why we want to run this command."
          }
        },
        "required" => ["command"],
        "additionalProperties" => false
      }
    }
  end

  @impl true
  def invoke(args, context) do
    metadata = Map.get(context, :metadata, %{})
    command = Map.get(args, "command") || Map.get(args, :command)

    # Resolve options from args, context, and metadata
    cwd = resolve_cwd(args, context, metadata)
    timeout_ms = resolve_timeout(args, context, metadata)
    max_bytes = Hosted.metadata_value(metadata, :max_output_bytes, @default_max_output_bytes)

    merged_context =
      context
      |> Map.put(:timeout_ms, timeout_ms)
      |> Map.put(:cwd, cwd)
      |> Map.put(:command, command)

    with {:ok, normalized} <- normalize_command(command),
         :ok <- check_approval(format_command_for_approval(normalized), metadata, merged_context) do
      execute_command(normalized, cwd, timeout_ms, max_bytes, args, merged_context, metadata)
    end
  end

  defp resolve_cwd(args, context, metadata) do
    Map.get(args, "workdir") ||
      Map.get(args, "cwd") ||
      Map.get(context, :cwd) ||
      Hosted.metadata_value(metadata, :cwd)
  end

  defp resolve_timeout(args, context, metadata) do
    Map.get(args, "timeout_ms") ||
      Map.get(args, "timeout") ||
      Map.get(context, :timeout_ms) ||
      Hosted.metadata_value(metadata, :timeout_ms, @default_timeout_ms)
  end

  defp check_approval(command, metadata, context) do
    case Hosted.callback(metadata, :approval) do
      nil ->
        :ok

      fun when is_function(fun, 2) ->
        handle_approval_result(fun.(command, context))

      fun when is_function(fun, 3) ->
        handle_approval_result(fun.(command, context, metadata))

      module when is_atom(module) ->
        if function_exported?(module, :review_tool, 2) do
          handle_approval_result(module.review_tool(command, context))
        else
          :ok
        end

      _ ->
        :ok
    end
  end

  defp handle_approval_result(:ok), do: :ok
  defp handle_approval_result(:allow), do: :ok
  defp handle_approval_result({:allow, _opts}), do: :ok
  defp handle_approval_result({:deny, reason}), do: {:error, {:approval_denied, reason}}
  defp handle_approval_result(:deny), do: {:error, {:approval_denied, :denied}}
  defp handle_approval_result(false), do: {:error, {:approval_denied, :denied}}
  defp handle_approval_result(_), do: :ok

  defp execute_command(command, cwd, timeout_ms, max_bytes, args, context, metadata) do
    case Hosted.callback(metadata, :executor) do
      nil ->
        # Use built-in executor
        case default_executor(command, cwd, timeout_ms) do
          {:ok, output, exit_code} ->
            {:ok, format_result(output, exit_code, max_bytes)}

          {:error, :timeout} ->
            {:error, :timeout}

          {:error, reason} ->
            {:error, reason}
        end

      fun when is_function(fun) ->
        # Use custom executor
        result = Hosted.safe_call(fun, args, context, metadata)
        handle_executor_result(result, max_bytes)
    end
  end

  defp handle_executor_result({:ok, output}, max_bytes) when is_binary(output) do
    {:ok, format_result(output, 0, max_bytes)}
  end

  defp handle_executor_result(
         {:ok, %{"output" => output, "exit_code" => code} = result},
         max_bytes
       ) do
    {:ok,
     format_result(output, code, max_bytes)
     |> Map.merge(Map.drop(result, ["output", "exit_code", "success"]))}
  end

  defp handle_executor_result({:ok, %{output: output, exit_code: code} = result}, max_bytes) do
    {:ok,
     format_result(output, code, max_bytes)
     |> Map.merge(Map.drop(result, [:output, :exit_code, :success]))}
  end

  defp handle_executor_result({:ok, output}, max_bytes) when is_map(output) do
    {:ok, Hosted.maybe_truncate_output(output, max_bytes)}
  end

  defp handle_executor_result({:error, reason}, _max_bytes), do: {:error, reason}

  defp handle_executor_result(output, max_bytes) when is_binary(output) do
    {:ok, format_result(output, 0, max_bytes)}
  end

  defp handle_executor_result(output, max_bytes) when is_map(output) do
    {:ok, Hosted.maybe_truncate_output(output, max_bytes)}
  end

  defp handle_executor_result(other, _max_bytes), do: {:ok, other}

  @doc false
  def default_executor(command, cwd, timeout_ms) do
    ensure_erlexec_started()

    opts =
      [:stdout, :stderr, :monitor]
      |> maybe_add_cd(cwd)

    exec_command = build_exec_command(command)

    case :exec.run(exec_command, opts) do
      {:ok, pid, os_pid} ->
        collect_output(os_pid, pid, timeout_ms)

      {:error, reason} ->
        {:error, {:exec_start_failed, reason}}
    end
  end

  defp build_exec_command(command) when is_list(command) do
    [exe | rest] = Enum.map(command, &to_string/1)
    resolved = resolve_executable_path(exe)

    Enum.map([resolved | rest], &to_charlist/1)
  end

  defp build_exec_command(command) when is_binary(command) do
    # Escape single quotes in command for shell
    escaped = String.replace(command, "'", "'\\''")
    ~c"sh -c '#{escaped}'"
  end

  defp build_exec_command(command), do: build_exec_command(to_string(command))

  defp normalize_command(command) when is_list(command) do
    normalized =
      command
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(&1 == ""))

    if normalized == [] do
      {:error, {:invalid_argument, :command}}
    else
      {:ok, normalized}
    end
  end

  defp normalize_command(command) when is_binary(command) and command != "" do
    {:ok, command}
  end

  defp normalize_command(_), do: {:error, {:invalid_argument, :command}}

  defp format_command_for_approval(command) when is_list(command) do
    Enum.join(command, " ")
  end

  defp format_command_for_approval(command), do: command

  defp maybe_add_cd(opts, nil), do: opts
  defp maybe_add_cd(opts, ""), do: opts
  defp maybe_add_cd(opts, cwd), do: [{:cd, to_charlist(cwd)} | opts]

  defp ensure_erlexec_started do
    case Application.ensure_all_started(:erlexec) do
      {:ok, _apps} -> :ok
      {:error, {:erlexec, {:already_started, _}}} -> :ok
      {:error, {:already_started, _}} -> :ok
      {:error, reason} -> raise "Failed to start erlexec: #{inspect(reason)}"
    end
  end

  defp collect_output(os_pid, pid, timeout_ms) do
    do_collect_output(os_pid, pid, timeout_ms, [], [])
  end

  defp do_collect_output(os_pid, pid, timeout_ms, stdout_acc, stderr_acc) do
    receive do
      {:stdout, ^os_pid, data} ->
        do_collect_output(os_pid, pid, timeout_ms, [data | stdout_acc], stderr_acc)

      {:stderr, ^os_pid, data} ->
        do_collect_output(os_pid, pid, timeout_ms, stdout_acc, [data | stderr_acc])

      {:DOWN, ^os_pid, :process, _proc, :normal} ->
        output = combine_output(stdout_acc, stderr_acc)
        {:ok, output, 0}

      {:DOWN, ^os_pid, :process, _proc, {:exit_status, status}} ->
        output = combine_output(stdout_acc, stderr_acc)
        {:ok, output, normalize_exit_status(status)}
    after
      timeout_ms ->
        safe_stop(pid)
        {:error, :timeout}
    end
  end

  defp safe_stop(pid) do
    if Process.alive?(pid) do
      try do
        :exec.stop(pid)
      rescue
        _ -> :ok
      end
    end
  end

  defp normalize_exit_status(raw_status) when is_integer(raw_status) do
    case :exec.status(raw_status) do
      {:status, code} -> code
      {:signal, signal, _core?} -> 128 + signal_to_int(signal)
    end
  rescue
    _ -> raw_status
  end

  defp normalize_exit_status(raw_status), do: raw_status

  defp signal_to_int(signal) when is_integer(signal), do: signal

  defp signal_to_int(signal) when is_atom(signal) do
    :exec.signal_to_int(signal)
  rescue
    _ -> 1
  end

  defp format_result(output, exit_code, max_bytes) do
    truncated = maybe_truncate(output, max_bytes)

    %{
      "output" => truncated,
      "exit_code" => exit_code,
      "success" => exit_code == 0
    }
  end

  defp maybe_truncate(output, nil), do: output
  defp maybe_truncate(output, max_bytes) when byte_size(output) <= max_bytes, do: output

  defp maybe_truncate(output, max_bytes) do
    String.slice(output, 0, max_bytes) <> "\n... (truncated)"
  end

  defp resolve_executable_path(executable) do
    cond do
      executable == "" ->
        executable

      String.contains?(executable, "/") ->
        executable

      true ->
        System.find_executable(executable) || executable
    end
  end

  defp combine_output(stdout_acc, stderr_acc) do
    stdout = stdout_acc |> Enum.reverse() |> IO.iodata_to_binary()
    stderr = stderr_acc |> Enum.reverse() |> IO.iodata_to_binary()

    cond do
      String.trim(stderr) != "" and String.trim(stdout) != "" ->
        stdout <> "\n" <> stderr

      String.trim(stderr) != "" ->
        stderr

      true ->
        stdout
    end
  end
end
