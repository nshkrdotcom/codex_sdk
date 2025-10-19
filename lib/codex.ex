defmodule Codex do
  @moduledoc """
  Public entry point for the Codex SDK.

  Provides helpers to start new threads or resume existing ones.
  """

  alias Codex.Options
  alias Codex.Thread
  alias Codex.Thread.Options, as: ThreadOptions

  @type start_opts :: map() | keyword() | Options.t()
  @type thread_opts :: map() | keyword() | ThreadOptions.t()

  @doc """
  Starts a new Codex thread returning a `%Codex.Thread{}` struct.
  """
  @spec start_thread(start_opts(), thread_opts()) ::
          {:ok, Thread.t()} | {:error, term()}
  def start_thread(opts \\ %{}, thread_opts \\ %{}) do
    with {:ok, codex_opts} <- normalize_options(opts),
         {:ok, thread_opts} <- normalize_thread_options(thread_opts) do
      {:ok, Thread.build(codex_opts, thread_opts)}
    end
  end

  @doc """
  Resumes an existing thread with the given `thread_id`.
  """
  @spec resume_thread(String.t(), start_opts(), thread_opts()) ::
          {:ok, Thread.t()} | {:error, term()}
  def resume_thread(thread_id, opts \\ %{}, thread_opts \\ %{})
      when is_binary(thread_id) do
    with {:ok, codex_opts} <- normalize_options(opts),
         {:ok, thread_opts} <- normalize_thread_options(thread_opts) do
      {:ok, Thread.build(codex_opts, thread_opts, thread_id: thread_id)}
    end
  end

  defp normalize_options(%Options{} = opts), do: {:ok, opts}
  defp normalize_options(opts), do: Options.new(opts)

  defp normalize_thread_options(%ThreadOptions{} = opts), do: {:ok, opts}
  defp normalize_thread_options(opts), do: ThreadOptions.new(opts)
end
