defmodule Codex.AppServer.V1 do
  @moduledoc """
  Legacy v1 app-server endpoints for compatibility with older servers.
  """

  alias Codex.AppServer.Connection
  alias Codex.AppServer.Params

  @type connection :: pid()

  @spec new_conversation(connection(), map() | keyword()) :: {:ok, map()} | {:error, term()}
  def new_conversation(conn, params \\ %{}) when is_pid(conn) do
    params = Params.normalize_map(params)

    wire_params = build_new_conversation_params(params)

    Connection.request(conn, "newConversation", wire_params, timeout_ms: 30_000)
  end

  @spec list_conversations(connection(), keyword()) :: {:ok, map()} | {:error, term()}
  def list_conversations(conn, opts \\ []) when is_pid(conn) and is_list(opts) do
    params =
      %{}
      |> Params.put_optional("pageSize", Keyword.get(opts, :page_size))
      |> Params.put_optional("cursor", Keyword.get(opts, :cursor))
      |> Params.put_optional("modelProviders", Keyword.get(opts, :model_providers))

    Connection.request(conn, "listConversations", params, timeout_ms: 30_000)
  end

  @spec resume_conversation(connection(), map() | keyword()) :: {:ok, map()} | {:error, term()}
  def resume_conversation(conn, params \\ %{}) when is_pid(conn) do
    params = Params.normalize_map(params)

    wire_params =
      %{}
      |> Params.put_optional("path", fetch_any(params, [:path, "path"]))
      |> Params.put_optional(
        "conversationId",
        fetch_any(params, [:conversation_id, "conversation_id", :conversationId, "conversationId"])
      )
      |> Params.put_optional("history", fetch_any(params, [:history, "history"]))
      |> Params.put_optional("overrides", encode_new_conversation_params(params))

    Connection.request(conn, "resumeConversation", wire_params, timeout_ms: 30_000)
  end

  @spec send_user_message(connection(), String.t(), String.t() | [map()]) ::
          {:ok, map()} | {:error, term()}
  def send_user_message(conn, conversation_id, input)
      when is_pid(conn) and is_binary(conversation_id) do
    params = %{"conversationId" => conversation_id, "items" => user_input_v1(input)}

    Connection.request(conn, "sendUserMessage", params, timeout_ms: 300_000)
  end

  @spec send_user_turn(connection(), String.t(), String.t() | [map()], keyword()) ::
          {:ok, map()} | {:error, term()}
  def send_user_turn(conn, conversation_id, input, opts \\ [])
      when is_pid(conn) and is_binary(conversation_id) and is_list(opts) do
    params =
      %{
        "conversationId" => conversation_id,
        "items" => user_input_v1(input)
      }
      |> Params.put_optional("cwd", Keyword.get(opts, :cwd))
      |> Params.put_optional(
        "approvalPolicy",
        opts |> Keyword.get(:approval_policy) |> Params.ask_for_approval()
      )
      |> Params.put_optional(
        "sandboxPolicy",
        opts |> Keyword.get(:sandbox_policy) |> sandbox_policy_v1()
      )
      |> Params.put_optional("model", Keyword.get(opts, :model))
      |> Params.put_optional("effort", opts |> Keyword.get(:effort) |> Params.reasoning_effort())
      |> Params.put_optional("summary", Keyword.get(opts, :summary))

    Connection.request(conn, "sendUserTurn", params, timeout_ms: 300_000)
  end

  @spec interrupt_conversation(connection(), String.t()) :: {:ok, map()} | {:error, term()}
  def interrupt_conversation(conn, conversation_id)
      when is_pid(conn) and is_binary(conversation_id) do
    params = %{"conversationId" => conversation_id}
    Connection.request(conn, "interruptConversation", params, timeout_ms: 30_000)
  end

  @spec add_conversation_listener(connection(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def add_conversation_listener(conn, conversation_id, opts \\ [])
      when is_pid(conn) and is_binary(conversation_id) and is_list(opts) do
    params =
      %{"conversationId" => conversation_id}
      |> Params.put_optional("experimentalRawEvents", Keyword.get(opts, :experimental_raw_events))

    Connection.request(conn, "addConversationListener", params, timeout_ms: 30_000)
  end

  @spec remove_conversation_listener(connection(), String.t()) :: {:ok, map()} | {:error, term()}
  def remove_conversation_listener(conn, subscription_id)
      when is_pid(conn) and is_binary(subscription_id) do
    params = %{"subscriptionId" => subscription_id}
    Connection.request(conn, "removeConversationListener", params, timeout_ms: 30_000)
  end

  defp encode_new_conversation_params(params) do
    case fetch_any(params, [:overrides, "overrides"]) do
      nil -> nil
      overrides -> build_new_conversation_params(Params.normalize_map(overrides))
    end
  end

  defp build_new_conversation_params(params) do
    %{}
    |> Params.put_optional("model", fetch_any(params, [:model, "model"]))
    |> Params.put_optional(
      "modelProvider",
      fetch_any(params, [:model_provider, "model_provider", :modelProvider, "modelProvider"])
    )
    |> Params.put_optional("profile", fetch_any(params, [:profile, "profile"]))
    |> Params.put_optional(
      "cwd",
      fetch_any(params, [:cwd, "cwd", :working_directory, "working_directory"])
    )
    |> Params.put_optional(
      "approvalPolicy",
      params
      |> fetch_any([:approval_policy, "approval_policy"])
      |> Params.ask_for_approval()
    )
    |> Params.put_optional(
      "sandbox",
      params
      |> fetch_any([:sandbox, "sandbox"])
      |> normalize_sandbox_mode_v1()
    )
    |> Params.put_optional("config", fetch_any(params, [:config, "config"]))
    |> Params.put_optional(
      "baseInstructions",
      fetch_any(params, [:base_instructions, "base_instructions"])
    )
    |> Params.put_optional(
      "developerInstructions",
      fetch_any(params, [:developer_instructions, "developer_instructions"])
    )
    |> Params.put_optional(
      "compactPrompt",
      fetch_any(params, [:compact_prompt, "compact_prompt", :compactPrompt, "compactPrompt"])
    )
    |> Params.put_optional(
      "includeApplyPatchTool",
      fetch_any(params, [
        :include_apply_patch_tool,
        "include_apply_patch_tool",
        :includeApplyPatchTool,
        "includeApplyPatchTool"
      ])
    )
  end

  defp user_input_v1(input) when is_binary(input) do
    [%{"type" => "text", "text" => input}]
  end

  defp user_input_v1(inputs) when is_list(inputs) do
    Enum.map(inputs, &user_input_block_v1/1)
  end

  defp user_input_block_v1(%{"type" => "text"} = block) do
    %{"type" => "text", "text" => Map.get(block, "text") || ""}
  end

  defp user_input_block_v1(%{type: :text} = block) do
    %{"type" => "text", "text" => Map.get(block, :text) || ""}
  end

  defp user_input_block_v1(%{"type" => "image"} = block) do
    %{
      "type" => "image",
      "imageUrl" =>
        fetch_any(block, [:imageUrl, "imageUrl", :image_url, "image_url", :url, "url"]) || ""
    }
  end

  defp user_input_block_v1(%{type: :image} = block) do
    %{
      "type" => "image",
      "imageUrl" =>
        fetch_any(block, [:imageUrl, "imageUrl", :image_url, "image_url", :url, "url"]) || ""
    }
  end

  defp user_input_block_v1(%{"type" => type} = block)
       when type in ["localImage", "local_image"] do
    %{"type" => "localImage", "path" => Map.get(block, "path") || ""}
  end

  defp user_input_block_v1(%{type: type} = block) when type in [:local_image, :localImage] do
    %{"type" => "localImage", "path" => Map.get(block, :path) || ""}
  end

  defp user_input_block_v1(text) when is_binary(text) do
    %{"type" => "text", "text" => text}
  end

  defp user_input_block_v1(other) when is_map(other) do
    other
    |> Params.normalize_map()
    |> Map.new()
    |> ensure_type()
  end

  defp ensure_type(%{"type" => _} = block), do: block
  defp ensure_type(block), do: Map.put(block, "type", "text")

  defp sandbox_policy_v1(nil), do: nil
  defp sandbox_policy_v1(%{} = policy), do: normalize_sandbox_policy_v1(policy)

  defp sandbox_policy_v1(policy) when is_list(policy),
    do: policy |> Map.new() |> normalize_sandbox_policy_v1()

  defp sandbox_policy_v1(policy) when is_atom(policy),
    do: %{"type" => normalize_policy_type_v1(policy)}

  defp sandbox_policy_v1(policy) when is_binary(policy),
    do: %{"type" => normalize_policy_type_v1(policy)}

  defp sandbox_policy_v1(_), do: nil

  defp normalize_sandbox_policy_v1(%{} = policy) do
    type =
      policy
      |> fetch_any([:type, "type"])
      |> normalize_policy_type_v1()

    %{}
    |> Params.put_optional("type", type)
    |> Params.put_optional(
      "writable_roots",
      fetch_any(policy, [:writable_roots, "writable_roots", :writableRoots, "writableRoots"])
    )
    |> Params.put_optional(
      "network_access",
      normalize_network_access_v1(
        type,
        fetch_any(policy, [:network_access, "network_access", :networkAccess, "networkAccess"])
      )
    )
    |> Params.put_optional(
      "exclude_tmpdir_env_var",
      fetch_any(policy, [
        :exclude_tmpdir_env_var,
        "exclude_tmpdir_env_var",
        :excludeTmpdirEnvVar,
        "excludeTmpdirEnvVar"
      ])
    )
    |> Params.put_optional(
      "exclude_slash_tmp",
      fetch_any(policy, [
        :exclude_slash_tmp,
        "exclude_slash_tmp",
        :excludeSlashTmp,
        "excludeSlashTmp"
      ])
    )
    |> case do
      %{} = result when map_size(result) == 0 -> nil
      %{} = result -> result
    end
  end

  defp normalize_sandbox_mode_v1(value) do
    case Params.sandbox_mode(value) do
      %{} -> nil
      other -> other
    end
  end

  defp normalize_policy_type_v1(nil), do: nil
  defp normalize_policy_type_v1(:read_only), do: "read-only"
  defp normalize_policy_type_v1("read-only"), do: "read-only"
  defp normalize_policy_type_v1("read_only"), do: "read-only"
  defp normalize_policy_type_v1("readOnly"), do: "read-only"
  defp normalize_policy_type_v1(:workspace_write), do: "workspace-write"
  defp normalize_policy_type_v1("workspace-write"), do: "workspace-write"
  defp normalize_policy_type_v1("workspace_write"), do: "workspace-write"
  defp normalize_policy_type_v1("workspaceWrite"), do: "workspace-write"
  defp normalize_policy_type_v1(:danger_full_access), do: "danger-full-access"
  defp normalize_policy_type_v1("danger-full-access"), do: "danger-full-access"
  defp normalize_policy_type_v1("danger_full_access"), do: "danger-full-access"
  defp normalize_policy_type_v1("dangerFullAccess"), do: "danger-full-access"
  defp normalize_policy_type_v1(:external_sandbox), do: "external-sandbox"
  defp normalize_policy_type_v1("external-sandbox"), do: "external-sandbox"
  defp normalize_policy_type_v1("external_sandbox"), do: "external-sandbox"
  defp normalize_policy_type_v1("externalSandbox"), do: "external-sandbox"
  defp normalize_policy_type_v1(value) when is_atom(value), do: value |> Atom.to_string()
  defp normalize_policy_type_v1(value) when is_binary(value), do: value
  defp normalize_policy_type_v1(_), do: nil

  defp normalize_network_access_v1("external-sandbox", value),
    do: normalize_external_network_access_v1(value)

  defp normalize_network_access_v1(_type, value) do
    case value do
      true -> true
      false -> false
      :enabled -> true
      :restricted -> false
      "enabled" -> true
      "restricted" -> false
      _ -> value
    end
  end

  defp normalize_external_network_access_v1(value) do
    case value do
      :enabled -> "enabled"
      :restricted -> "restricted"
      true -> "enabled"
      false -> "restricted"
      "enabled" -> "enabled"
      "restricted" -> "restricted"
      other -> other
    end
  end

  defp fetch_any(map, keys) when is_list(keys) and is_map(map) do
    Enum.reduce_while(keys, nil, fn key, _acc ->
      case Map.fetch(map, key) do
        {:ok, value} -> {:halt, value}
        :error -> {:cont, nil}
      end
    end)
  end
end
