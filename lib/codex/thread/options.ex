defmodule Codex.Thread.Options do
  @moduledoc """
  Per-thread configuration options.
  """

  alias Codex.FileSearch

  @enforce_keys []
  defstruct metadata: %{},
            labels: %{},
            auto_run: false,
            approval_policy: nil,
            approval_hook: nil,
            approval_timeout_ms: 30_000,
            sandbox: :default,
            working_directory: nil,
            additional_directories: [],
            skip_git_repo_check: false,
            network_access_enabled: nil,
            web_search_enabled: false,
            ask_for_approval: nil,
            attachments: [],
            file_search: nil

  @type t :: %__MODULE__{
          metadata: map(),
          labels: map(),
          auto_run: boolean(),
          approval_policy: module() | nil,
          approval_hook: module() | nil,
          approval_timeout_ms: pos_integer(),
          sandbox:
            :default
            | :strict
            | :permissive
            | :read_only
            | :workspace_write
            | :danger_full_access
            | String.t(),
          working_directory: String.t() | nil,
          additional_directories: [String.t()],
          skip_git_repo_check: boolean(),
          network_access_enabled: boolean() | nil,
          web_search_enabled: boolean(),
          ask_for_approval: :untrusted | :on_failure | :on_request | :never | String.t() | nil,
          attachments: [map()] | [],
          file_search: FileSearch.t() | nil
        }

  @doc """
  Builds a thread options struct from various inputs.
  """
  @spec new(map() | keyword() | t()) :: {:ok, t()} | {:error, term()}
  def new(%__MODULE__{} = opts), do: {:ok, opts}
  def new(attrs) when is_list(attrs), do: attrs |> Map.new() |> new()

  def new(attrs) when is_map(attrs) do
    metadata = Map.get(attrs, :metadata, Map.get(attrs, "metadata", %{}))
    labels = Map.get(attrs, :labels, Map.get(attrs, "labels", %{}))
    auto_run = Map.get(attrs, :auto_run, Map.get(attrs, "auto_run", false))
    approval_policy = Map.get(attrs, :approval_policy, Map.get(attrs, "approval_policy"))
    approval_hook = Map.get(attrs, :approval_hook, Map.get(attrs, "approval_hook"))

    approval_timeout_ms =
      Map.get(attrs, :approval_timeout_ms, Map.get(attrs, "approval_timeout_ms", 30_000))

    sandbox = Map.get(attrs, :sandbox, Map.get(attrs, "sandbox", :default))

    working_directory =
      Map.get(attrs, :working_directory, Map.get(attrs, "working_directory", Map.get(attrs, :cd)))

    additional_directories =
      Map.get(attrs, :additional_directories, Map.get(attrs, "additional_directories", []))

    skip_git_repo_check =
      Map.get(attrs, :skip_git_repo_check, Map.get(attrs, "skip_git_repo_check", false))

    network_access_enabled =
      Map.get(attrs, :network_access_enabled, Map.get(attrs, "network_access_enabled"))

    web_search_enabled =
      Map.get(attrs, :web_search_enabled, Map.get(attrs, "web_search_enabled", false))

    ask_for_approval = Map.get(attrs, :ask_for_approval, Map.get(attrs, "ask_for_approval"))
    attachments = Map.get(attrs, :attachments, Map.get(attrs, "attachments", []))
    file_search = Map.get(attrs, :file_search, Map.get(attrs, "file_search"))

    with {:ok, metadata} <- ensure_map(metadata, :metadata),
         {:ok, labels} <- ensure_map(labels, :labels),
         {:ok, attachments} <- ensure_list(attachments, :attachments),
         {:ok, file_search} <- FileSearch.new(file_search),
         {:ok, sandbox} <- normalize_sandbox(sandbox),
         true <- is_boolean(auto_run) or {:error, {:invalid_auto_run, auto_run}},
         :ok <- validate_optional_string(working_directory, :working_directory),
         {:ok, additional_directories} <-
           normalize_string_list(additional_directories, :additional_directories),
         true <-
           is_boolean(skip_git_repo_check) or
             {:error, {:invalid_skip_git_repo_check, skip_git_repo_check}},
         {:ok, network_access_enabled} <-
           validate_optional_boolean(network_access_enabled, :network_access_enabled),
         true <-
           is_boolean(web_search_enabled) or
             {:error, {:invalid_web_search_enabled, web_search_enabled}},
         {:ok, ask_for_approval} <- normalize_ask_for_approval(ask_for_approval),
         true <-
           (is_integer(approval_timeout_ms) and approval_timeout_ms > 0) or
             {:error, {:invalid_timeout, approval_timeout_ms}} do
      {:ok,
       %__MODULE__{
         metadata: metadata,
         labels: labels,
         auto_run: auto_run,
         approval_policy: approval_policy,
         approval_hook: approval_hook,
         approval_timeout_ms: approval_timeout_ms,
         sandbox: sandbox,
         working_directory: working_directory,
         additional_directories: additional_directories,
         skip_git_repo_check: skip_git_repo_check,
         network_access_enabled: network_access_enabled,
         web_search_enabled: web_search_enabled,
         ask_for_approval: ask_for_approval,
         attachments: attachments,
         file_search: file_search
       }}
    else
      {:error, _} = error -> error
    end
  end

  defp ensure_map(value, _field) when is_map(value), do: {:ok, value}
  defp ensure_map(nil, _field), do: {:ok, %{}}
  defp ensure_map(value, field), do: {:error, {:invalid_map, field, value}}

  defp ensure_list(value, _field) when is_list(value), do: {:ok, value}
  defp ensure_list(nil, _field), do: {:ok, []}
  defp ensure_list(value, field), do: {:error, {:invalid_list, field, value}}

  defp validate_optional_string(nil, _field), do: :ok
  defp validate_optional_string(value, _field) when is_binary(value), do: :ok
  defp validate_optional_string(value, field), do: {:error, {:"invalid_#{field}", value}}

  defp validate_optional_boolean(nil, _field), do: {:ok, nil}
  defp validate_optional_boolean(value, _field) when is_boolean(value), do: {:ok, value}
  defp validate_optional_boolean(value, field), do: {:error, {:"invalid_#{field}", value}}

  defp normalize_string_list(list, _field) when list in [nil, []], do: {:ok, []}

  defp normalize_string_list(list, field) when is_list(list) do
    if Enum.all?(list, &is_binary/1) do
      {:ok, list}
    else
      {:error, {:invalid_list, field, list}}
    end
  end

  defp normalize_string_list(value, field), do: {:error, {:invalid_list, field, value}}

  defp normalize_sandbox(nil), do: {:ok, :default}
  defp normalize_sandbox(:default), do: {:ok, :default}
  defp normalize_sandbox(:strict), do: {:ok, :strict}
  defp normalize_sandbox(:permissive), do: {:ok, :permissive}
  defp normalize_sandbox(:read_only), do: {:ok, :read_only}
  defp normalize_sandbox(:workspace_write), do: {:ok, :workspace_write}
  defp normalize_sandbox(:danger_full_access), do: {:ok, :danger_full_access}
  defp normalize_sandbox("read-only"), do: {:ok, :read_only}
  defp normalize_sandbox("workspace-write"), do: {:ok, :workspace_write}
  defp normalize_sandbox("danger-full-access"), do: {:ok, :danger_full_access}

  defp normalize_sandbox(value) when is_binary(value) do
    # Accept arbitrary strings for forward compatibility with the upstream CLI, but
    # keep validating common values.
    {:ok, value}
  end

  defp normalize_sandbox(value), do: {:error, {:invalid_sandbox, value}}

  defp normalize_ask_for_approval(nil), do: {:ok, nil}
  defp normalize_ask_for_approval(:untrusted), do: {:ok, :untrusted}
  defp normalize_ask_for_approval(:on_failure), do: {:ok, :on_failure}
  defp normalize_ask_for_approval(:on_request), do: {:ok, :on_request}
  defp normalize_ask_for_approval(:never), do: {:ok, :never}
  defp normalize_ask_for_approval("untrusted"), do: {:ok, :untrusted}
  defp normalize_ask_for_approval("on-failure"), do: {:ok, :on_failure}
  defp normalize_ask_for_approval("on-request"), do: {:ok, :on_request}
  defp normalize_ask_for_approval("never"), do: {:ok, :never}
  defp normalize_ask_for_approval(value) when is_binary(value), do: {:ok, value}
  defp normalize_ask_for_approval(value), do: {:error, {:invalid_ask_for_approval, value}}
end
