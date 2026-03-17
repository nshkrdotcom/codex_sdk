defmodule Codex.OAuth.Browser do
  @moduledoc false

  alias Codex.OAuth.Environment

  @type opener_result :: :ok | {:error, term()}

  @spec open(String.t(), Environment.t(), keyword()) :: opener_result()
  def open(url, %Environment{} = environment, opts \\ [])
      when is_binary(url) and is_list(opts) do
    case Keyword.get(opts, :opener) || Keyword.get(opts, :browser_opener) do
      fun when is_function(fun, 1) ->
        fun.(url)

      _ ->
        do_open(url, environment)
    end
  end

  @spec command(Environment.t()) :: [String.t()] | nil
  def command(%Environment{wsl?: true}) do
    cond do
      System.find_executable("wslview") -> ["wslview"]
      System.find_executable("cmd.exe") -> ["cmd.exe", "/c", "start", ""]
      true -> nil
    end
  end

  def command(%Environment{os: :macos}), do: ["open"]

  def command(%Environment{os: :windows}) do
    if System.find_executable("cmd.exe"), do: ["cmd.exe", "/c", "start", ""], else: nil
  end

  def command(%Environment{os: :linux}) do
    if System.find_executable("xdg-open"), do: ["xdg-open"], else: nil
  end

  def command(%Environment{}), do: nil

  defp do_open(url, %Environment{} = environment) do
    case command(environment) do
      nil ->
        {:error, :browser_unavailable}

      [program | args] ->
        case System.cmd(program, args ++ [url], stderr_to_stdout: true) do
          {_output, 0} -> :ok
          {output, status} -> {:error, {:browser_open_failed, status, output}}
        end
    end
  rescue
    error -> {:error, error}
  end
end
