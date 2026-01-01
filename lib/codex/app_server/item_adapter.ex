defmodule Codex.AppServer.ItemAdapter do
  @moduledoc false

  alias Codex.Items

  @spec to_item(map()) :: {:ok, Items.t()} | {:raw, map()}
  def to_item(%{"type" => "userMessage"} = item) do
    {:ok,
     %Items.UserMessage{
       id: Map.get(item, "id"),
       content: Map.get(item, "content") || []
     }}
  end

  def to_item(%{"type" => "agentMessage"} = item) do
    {:ok,
     %Items.AgentMessage{
       id: Map.get(item, "id"),
       text: Map.get(item, "text") || ""
     }}
  end

  def to_item(%{"type" => "reasoning"} = item) do
    summary = normalize_reasoning_part(Map.get(item, "summary"))
    content = normalize_reasoning_part(Map.get(item, "content"))

    {:ok,
     %Items.Reasoning{
       id: Map.get(item, "id"),
       text: join_reasoning_text(summary, content) || "",
       summary: summary,
       content: content
     }}
  end

  def to_item(%{"type" => "commandExecution"} = item) do
    {:ok,
     %Items.CommandExecution{
       id: Map.get(item, "id"),
       command: Map.get(item, "command") || "",
       cwd: Map.get(item, "cwd"),
       process_id: Map.get(item, "processId"),
       command_actions: Map.get(item, "commandActions") || [],
       aggregated_output: Map.get(item, "aggregatedOutput") || "",
       exit_code: Map.get(item, "exitCode"),
       status: normalize_status(Map.get(item, "status")),
       duration_ms: Map.get(item, "durationMs")
     }}
  end

  def to_item(%{"type" => "fileChange"} = item) do
    {:ok,
     %Items.FileChange{
       id: Map.get(item, "id"),
       status: normalize_status(Map.get(item, "status")),
       changes: normalize_file_changes(Map.get(item, "changes") || [])
     }}
  end

  def to_item(%{"type" => "mcpToolCall"} = item) do
    {:ok,
     %Items.McpToolCall{
       id: Map.get(item, "id"),
       server: Map.get(item, "server") || "",
       tool: Map.get(item, "tool") || "",
       arguments: Map.get(item, "arguments"),
       result: Map.get(item, "result"),
       error: Map.get(item, "error"),
       status: normalize_status(Map.get(item, "status")),
       duration_ms: Map.get(item, "durationMs")
     }}
  end

  def to_item(%{"type" => "webSearch"} = item) do
    {:ok,
     %Items.WebSearch{
       id: Map.get(item, "id"),
       query: Map.get(item, "query") || ""
     }}
  end

  def to_item(%{"type" => "imageView"} = item) do
    {:ok,
     %Items.ImageView{
       id: Map.get(item, "id"),
       path: Map.get(item, "path") || ""
     }}
  end

  def to_item(%{"type" => "enteredReviewMode"} = item) do
    {:ok,
     %Items.ReviewMode{
       id: Map.get(item, "id"),
       entered: true,
       review: Map.get(item, "review") || ""
     }}
  end

  def to_item(%{"type" => "exitedReviewMode"} = item) do
    {:ok,
     %Items.ReviewMode{
       id: Map.get(item, "id"),
       entered: false,
       review: Map.get(item, "review") || ""
     }}
  end

  def to_item(%{"type" => _type} = item), do: {:raw, item}
  def to_item(item) when is_map(item), do: {:raw, item}

  @spec to_raw_item(map()) :: {:ok, Items.t()} | {:raw, map()}
  def to_raw_item(%{"type" => _type} = item) do
    case Items.parse_raw_response_item(item) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _} -> {:raw, item}
    end
  end

  def to_raw_item(item) when is_map(item), do: {:raw, item}

  defp normalize_file_changes(changes) when is_list(changes) do
    Enum.map(changes, fn change ->
      %{path: Map.get(change, "path") || "", kind: :update}
      |> maybe_put(:diff, Map.get(change, "diff"))
      |> then(fn base ->
        kind = Map.get(change, "kind")
        {kind_atom, move_path} = normalize_patch_change_kind(kind)

        base
        |> Map.put(:kind, kind_atom)
        |> maybe_put(:move_path, move_path)
      end)
    end)
  end

  defp normalize_file_changes(_changes), do: []

  defp normalize_patch_change_kind(%{"type" => "add"}), do: {:add, nil}
  defp normalize_patch_change_kind(%{"type" => "delete"}), do: {:delete, nil}

  defp normalize_patch_change_kind(%{"type" => "update"} = kind),
    do: {:update, Map.get(kind, "movePath")}

  defp normalize_patch_change_kind(_kind), do: {:update, nil}

  defp normalize_status(nil), do: :in_progress

  defp normalize_status(value) when is_atom(value), do: value

  defp normalize_status(value) when is_binary(value) do
    case value do
      "inProgress" -> :in_progress
      "completed" -> :completed
      "failed" -> :failed
      "declined" -> :declined
      _other -> :in_progress
    end
  end

  defp normalize_status(_), do: :in_progress

  defp normalize_reasoning_part(nil), do: []
  defp normalize_reasoning_part(list) when is_list(list), do: Enum.map(list, &to_string/1)
  defp normalize_reasoning_part(value) when is_binary(value), do: [value]
  defp normalize_reasoning_part(value), do: [to_string(value)]

  defp join_reasoning_text(summary, content) do
    parts =
      []
      |> maybe_concat_lines(summary)
      |> maybe_concat_lines(content)

    if parts == [] do
      nil
    else
      Enum.join(parts, "\n")
    end
  end

  defp maybe_concat_lines(parts, lines) when is_list(lines) do
    parts ++ Enum.map(lines, &to_string/1)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
