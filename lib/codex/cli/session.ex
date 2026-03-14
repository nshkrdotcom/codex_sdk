defmodule Codex.CLI.Session do
  @moduledoc """
  Raw `codex` CLI subprocess session.

  Sessions are useful for interactive or long-running commands such as:

  - `codex`
  - `codex resume`
  - `codex fork`
  - `codex app-server`
  - `codex mcp-server`

  The caller process receives raw `erlexec` messages for the spawned process:

  - `{:stdout, os_pid, binary}`
  - `{:stderr, os_pid, binary}`
  - `{:DOWN, os_pid, :process, pid, reason}`

  Use `collect/2` to accumulate output until the process exits.
  """

  alias Codex.Config.Defaults
  alias Codex.ProcessExit
  alias Codex.Runtime.Erlexec

  @enforce_keys [:args, :command, :os_pid, :pid, :receiver]
  defstruct [:args, :command, :os_pid, :pid, :receiver, pty?: false, stdin?: false]

  @type t :: %__MODULE__{
          args: [String.t()],
          command: [String.t()],
          os_pid: non_neg_integer(),
          pid: pid(),
          receiver: pid(),
          pty?: boolean(),
          stdin?: boolean()
        }

  @type result :: %{
          command: [String.t()],
          args: [String.t()],
          stdout: String.t(),
          stderr: String.t(),
          exit_code: integer(),
          success: boolean()
        }

  @doc """
  Starts a raw subprocess session for `binary_path` and `args`.
  """
  @spec start(String.t(), [String.t()], keyword()) :: {:ok, t()} | {:error, term()}
  def start(binary_path, args, opts \\ [])
      when is_binary(binary_path) and is_list(args) and is_list(opts) do
    receiver = Keyword.get(opts, :receiver, self())
    pty? = Keyword.get(opts, :pty, false)
    stdin? = Keyword.get(opts, :stdin, false)

    with :ok <- Erlexec.ensure_started(),
         exec_opts <- build_exec_opts(receiver, opts, pty?, stdin?),
         argv <- normalize_argv(binary_path, args),
         {:ok, pid, os_pid} <- exec_run(argv, exec_opts) do
      {:ok,
       %__MODULE__{
         args: args,
         command: [binary_path | args],
         os_pid: os_pid,
         pid: pid,
         receiver: receiver,
         pty?: pty?,
         stdin?: stdin?
       }}
    end
  end

  @doc """
  Sends input bytes to the subprocess stdin.
  """
  @spec send_input(t(), iodata()) :: :ok | {:error, term()}
  def send_input(%__MODULE__{stdin?: false}, _data), do: {:error, :stdin_unavailable}

  def send_input(%__MODULE__{pid: pid}, data) do
    :exec.send(pid, IO.iodata_to_binary(data))
  catch
    :exit, reason -> {:error, reason}
  end

  @doc """
  Closes the subprocess stdin by sending EOF.
  """
  @spec close_input(t()) :: :ok | {:error, term()}
  def close_input(%__MODULE__{stdin?: false}), do: {:error, :stdin_unavailable}

  def close_input(%__MODULE__{pid: pid}) do
    :exec.send(pid, :eof)
  catch
    :exit, reason -> {:error, reason}
  end

  @doc """
  Stops the subprocess.
  """
  @spec stop(t()) :: :ok | {:error, term()}
  def stop(%__MODULE__{pid: pid}) do
    :exec.stop(pid)
  catch
    :exit, reason -> {:error, reason}
  end

  @doc """
  Interrupts the subprocess.
  """
  @spec interrupt(t()) :: :ok | {:error, term()}
  def interrupt(%__MODULE__{pid: pid, pty?: true}) do
    :exec.send(pid, <<3>>)
  catch
    :exit, reason -> {:error, reason}
  end

  def interrupt(%__MODULE__{} = session), do: stop(session)

  @doc """
  Collects stdout/stderr until the subprocess exits.
  """
  @spec collect(t(), timeout()) :: {:ok, result()} | {:error, term()}
  def collect(%__MODULE__{} = session, timeout_ms \\ Defaults.exec_timeout_ms()) do
    do_collect(session, timeout_ms, [], [])
  end

  defp do_collect(%__MODULE__{os_pid: os_pid, pid: pid} = session, timeout_ms, stdout, stderr) do
    receive do
      {:stdout, ^os_pid, data} ->
        do_collect(session, timeout_ms, [data | stdout], stderr)

      {:stderr, ^os_pid, data} ->
        do_collect(session, timeout_ms, stdout, [data | stderr])

      {:DOWN, ^os_pid, :process, ^pid, reason} ->
        exit_code = exit_code(reason)

        {:ok,
         %{
           command: session.command,
           args: session.args,
           stdout: stdout |> Enum.reverse() |> IO.iodata_to_binary(),
           stderr: stderr |> Enum.reverse() |> IO.iodata_to_binary(),
           exit_code: exit_code,
           success: exit_code == 0
         }}
    after
      timeout_ms ->
        {:error, {:timeout, session}}
    end
  end

  defp build_exec_opts(receiver, opts, pty?, stdin?) do
    []
    |> maybe_put_cd(Keyword.get(opts, :cwd))
    |> maybe_put_env(Keyword.get(opts, :env, []))
    |> maybe_put_stdin(stdin?)
    |> maybe_put_pty(pty?)
    |> Kernel.++([{:stdout, receiver}, {:stderr, receiver}, :monitor])
  end

  defp maybe_put_cd(exec_opts, nil), do: exec_opts
  defp maybe_put_cd(exec_opts, cwd), do: [{:cd, to_charlist(cwd)} | exec_opts]

  defp maybe_put_env(exec_opts, []), do: exec_opts
  defp maybe_put_env(exec_opts, nil), do: exec_opts
  defp maybe_put_env(exec_opts, env), do: [{:env, env} | exec_opts]

  defp maybe_put_stdin(exec_opts, true), do: [:stdin | exec_opts]
  defp maybe_put_stdin(exec_opts, _), do: exec_opts

  defp maybe_put_pty(exec_opts, true), do: [:pty | exec_opts]
  defp maybe_put_pty(exec_opts, _), do: exec_opts

  defp normalize_argv(binary_path, args) do
    [binary_path | Enum.map(args, &to_string/1)]
    |> Enum.map(&to_charlist/1)
  end

  defp exec_run(argv, exec_opts) do
    :exec.run(argv, exec_opts)
  catch
    :exit, reason -> {:error, reason}
  end

  defp exit_code(reason) do
    case ProcessExit.exit_status(reason) do
      {:ok, status} -> status
      :unknown -> -1
    end
  end
end
