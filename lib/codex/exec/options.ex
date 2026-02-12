defmodule Codex.Exec.Options do
  @moduledoc false

  alias Codex.Files.Attachment
  alias Codex.Options

  @enforce_keys [:codex_opts]
  defstruct codex_opts: nil,
            thread: nil,
            turn_opts: %{},
            continuation_token: nil,
            attachments: [],
            output_schema_path: nil,
            tool_outputs: [],
            tool_failures: [],
            env: %{},
            clear_env?: nil,
            cancellation_token: nil,
            timeout_ms: nil,
            stream_idle_timeout_ms: nil,
            max_stderr_buffer_bytes: nil

  @type t :: %__MODULE__{
          codex_opts: Options.t(),
          thread: Codex.Thread.t() | nil,
          turn_opts: map(),
          continuation_token: String.t() | nil,
          attachments: [Attachment.t()],
          output_schema_path: String.t() | nil,
          tool_outputs: [map()],
          tool_failures: [map()],
          env: map(),
          clear_env?: boolean() | nil,
          cancellation_token: String.t() | nil,
          timeout_ms: pos_integer() | nil,
          stream_idle_timeout_ms: pos_integer() | nil,
          max_stderr_buffer_bytes: pos_integer() | nil
        }

  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = opts), do: {:ok, opts}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    codex_opts = Map.get(attrs, :codex_opts, Map.get(attrs, "codex_opts"))
    thread = Map.get(attrs, :thread, Map.get(attrs, "thread"))
    turn_opts = Map.get(attrs, :turn_opts, Map.get(attrs, "turn_opts", %{}))
    continuation_token = Map.get(attrs, :continuation_token, Map.get(attrs, "continuation_token"))
    attachments = Map.get(attrs, :attachments, Map.get(attrs, "attachments", []))
    output_schema_path = Map.get(attrs, :output_schema_path, Map.get(attrs, "output_schema_path"))
    tool_outputs = Map.get(attrs, :tool_outputs, Map.get(attrs, "tool_outputs", []))
    tool_failures = Map.get(attrs, :tool_failures, Map.get(attrs, "tool_failures", []))
    env = Map.get(attrs, :env, Map.get(attrs, "env", %{}))
    clear_env? = Map.get(attrs, :clear_env?, Map.get(attrs, "clear_env?"))
    cancellation_token = Map.get(attrs, :cancellation_token, Map.get(attrs, "cancellation_token"))
    timeout_ms = Map.get(attrs, :timeout_ms, Map.get(attrs, "timeout_ms"))

    stream_idle_timeout_ms =
      Map.get(attrs, :stream_idle_timeout_ms, Map.get(attrs, "stream_idle_timeout_ms"))

    max_stderr_buffer_bytes =
      Map.get(attrs, :max_stderr_buffer_bytes, Map.get(attrs, "max_stderr_buffer_bytes"))

    with {:ok, codex_opts} <- ensure_codex_opts(codex_opts),
         {:ok, turn_opts} <- ensure_map(turn_opts, :turn_opts),
         {:ok, attachments} <- ensure_list(attachments, :attachments),
         {:ok, tool_outputs} <- ensure_list(tool_outputs, :tool_outputs),
         {:ok, tool_failures} <- ensure_list(tool_failures, :tool_failures),
         {:ok, env} <- normalize_env(env),
         {:ok, clear_env?} <- validate_optional_boolean(clear_env?, :clear_env?),
         :ok <- validate_cancellation_token(cancellation_token),
         :ok <- validate_timeout(timeout_ms),
         :ok <- validate_optional_timeout(stream_idle_timeout_ms, :stream_idle_timeout_ms),
         :ok <-
           validate_optional_positive_integer(max_stderr_buffer_bytes, :max_stderr_buffer_bytes) do
      {:ok,
       %__MODULE__{
         codex_opts: codex_opts,
         thread: thread,
         turn_opts: turn_opts,
         continuation_token: continuation_token,
         attachments: attachments,
         output_schema_path: output_schema_path,
         tool_outputs: tool_outputs,
         tool_failures: tool_failures,
         env: env,
         clear_env?: clear_env?,
         cancellation_token: cancellation_token,
         timeout_ms: timeout_ms,
         stream_idle_timeout_ms: stream_idle_timeout_ms,
         max_stderr_buffer_bytes: max_stderr_buffer_bytes
       }}
    else
      {:error, _} = error -> error
    end
  end

  defp ensure_codex_opts(%Options{} = opts), do: {:ok, opts}
  defp ensure_codex_opts(_), do: {:error, :missing_options}

  defp ensure_map(value, _field) when is_map(value), do: {:ok, value}
  defp ensure_map(nil, _field), do: {:ok, %{}}
  defp ensure_map(value, field), do: {:error, {:invalid_map, field, value}}

  defp ensure_list(value, _field) when is_list(value), do: {:ok, value}
  defp ensure_list(nil, _field), do: {:ok, []}
  defp ensure_list(value, field), do: {:error, {:invalid_list, field, value}}

  defp normalize_env(env) when env in [%{}, nil, []], do: {:ok, %{}}

  defp normalize_env(env) when is_map(env) do
    normalized =
      env
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.into(%{}, fn {key, value} ->
        {to_string(key), normalize_env_value(value)}
      end)

    {:ok, normalized}
  end

  defp normalize_env(env) when is_list(env) do
    if Keyword.keyword?(env) do
      env
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.into(%{}, fn {key, value} ->
        {to_string(key), normalize_env_value(value)}
      end)
      |> then(&{:ok, &1})
    else
      {:error, {:invalid_env, env}}
    end
  end

  defp normalize_env(env), do: {:error, {:invalid_env, env}}

  defp normalize_env_value(value) when is_binary(value), do: value
  defp normalize_env_value(value), do: to_string(value)

  defp validate_cancellation_token(nil), do: :ok

  defp validate_cancellation_token(token) when is_binary(token) and token != "" do
    :ok
  end

  defp validate_cancellation_token(token), do: {:error, {:invalid_cancellation_token, token}}

  defp validate_optional_boolean(nil, _field), do: {:ok, nil}
  defp validate_optional_boolean(value, _field) when is_boolean(value), do: {:ok, value}
  defp validate_optional_boolean(value, field), do: {:error, {:"invalid_#{field}", value}}

  defp validate_timeout(nil), do: :ok
  defp validate_timeout(timeout) when is_integer(timeout) and timeout > 0, do: :ok
  defp validate_timeout(timeout), do: {:error, {:invalid_timeout, timeout}}

  defp validate_optional_timeout(nil, _field), do: :ok

  defp validate_optional_timeout(timeout, _field) when is_integer(timeout) and timeout > 0,
    do: :ok

  defp validate_optional_timeout(timeout, field),
    do: {:error, {:"invalid_#{field}", timeout}}

  defp validate_optional_positive_integer(nil, _field), do: :ok

  defp validate_optional_positive_integer(value, _field)
       when is_integer(value) and value > 0,
       do: :ok

  defp validate_optional_positive_integer(value, field),
    do: {:error, {:"invalid_#{field}", value}}
end
