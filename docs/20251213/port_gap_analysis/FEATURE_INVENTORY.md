# Complete Feature Inventory - All Three SDKs

**Date**: 2025-12-13
**Purpose**: Detailed feature-by-feature comparison for porting reference

---

## 1. CORE MODULES COMPARISON

### 1.1 Entry Points

| Feature | TypeScript (codex/) | Python (openai-agents-python/) | Elixir (codex_sdk/) |
|---------|---------------------|-------------------------------|---------------------|
| Main class | `Codex` | `Agent` + `Runner` | `Codex` |
| Thread/session | `Thread` | `RunResult` | `Codex.Thread` |
| Start new | `startThread()` | `Runner.run()` | `start_thread/2` |
| Resume | `resumeThread(id)` | via session | `resume_thread/3` |

### 1.2 Configuration Systems

| Option | TypeScript | Python | Elixir |
|--------|-----------|--------|--------|
| API Key | `apiKey` | via OpenAI client | `api_key` |
| Base URL | `baseUrl` | via OpenAI client | `base_url` |
| Model | per-thread | `Agent.model` | `model` in Options |
| Reasoning Effort | `modelReasoningEffort` | `ModelSettings.reasoning` | `reasoning_effort` |
| Sandbox | `sandboxMode` | N/A | `sandbox` |
| Working Dir | `workingDirectory` | N/A | via env |
| Network Access | `networkAccessEnabled` | N/A | via codex flags |
| Web Search | `webSearchEnabled` | `WebSearchTool` | via codex flags |
| Approval Policy | `approvalPolicy` | N/A | `approval_policy` |

### 1.3 Model Settings

| Setting | TypeScript | Python | Elixir |
|---------|-----------|--------|--------|
| Temperature | N/A | `temperature` | `temperature` |
| Top P | N/A | `top_p` | `top_p` |
| Max Tokens | N/A | `max_tokens` | `max_tokens` |
| Frequency Penalty | N/A | `frequency_penalty` | `frequency_penalty` |
| Presence Penalty | N/A | `presence_penalty` | `presence_penalty` |
| Tool Choice | N/A | `tool_choice` | `tool_choice` |
| Parallel Tools | N/A | `parallel_tool_calls` | `parallel_tool_calls` |
| Truncation | N/A | `truncation` | `truncation` |
| Reasoning | N/A | `reasoning` | `reasoning` |
| Store | N/A | `store` | `store` |
| Prompt Cache | N/A | `prompt_cache_retention` | `prompt_cache` |

---

## 2. AGENT SYSTEM COMPARISON

### 2.1 Agent Definition

| Field | TypeScript | Python | Elixir |
|-------|-----------|--------|--------|
| Name | N/A | `name` | `name` |
| Instructions | N/A | `instructions` | `instructions` |
| System Prompt | via codex | `instructions` (callable) | `instructions` |
| Tools | N/A | `tools` | `tools` |
| Handoffs | N/A | `handoffs` | `handoffs` |
| Model Override | N/A | `model` | `model` |
| Model Settings | N/A | `model_settings` | `model_settings` |
| Input Guardrails | N/A | `input_guardrails` | `input_guardrails` |
| Output Guardrails | N/A | `output_guardrails` | `output_guardrails` |
| Output Type | N/A | `output_type` | via output_schema |
| Dynamic Prompt | N/A | `prompt` | `prompt` |
| Hooks | N/A | `hooks` | `hooks` |
| MCP Servers | N/A | `mcp_servers` | via MCP.Client |
| Handoff Desc | N/A | `handoff_description` | `handoff_description` |

### 2.2 Tool Use Behavior

| Behavior | Python | Elixir |
|----------|--------|--------|
| Run LLM Again | `:run_llm_again` | `:run_llm_again` |
| Stop on First | `:stop_on_first_tool` | `:stop_on_first_tool` |
| Stop at Names | `{"stop_at_tool_names": [...]}` | `%{stop_at_tool_names: [...]}` |
| Custom Function | callable | function |

---

## 3. TOOL SYSTEM COMPARISON

### 3.1 Tool Definition

| Feature | TypeScript | Python | Elixir |
|---------|-----------|--------|--------|
| Decorator/Macro | N/A | `@function_tool` | `use Codex.FunctionTool` |
| Name | from MCP | `name` | `:name` |
| Description | from MCP | docstring or explicit | `:description` |
| Parameters | from MCP | type hints + docstring | `:parameters` map |
| Required | from MCP | type hints | `:required` list |
| Schema | from MCP | auto-generated | `:schema` or generated |
| Strict Mode | from MCP | `strict_json_schema` | `:strict?` |
| Handler | from MCP | function body | `:handler` |
| Enabled Check | from MCP | `is_enabled` | `:enabled?` |
| Error Handler | N/A | `failure_error_function` | `:on_error` |

### 3.2 Hosted Tools

| Tool | TypeScript | Python | Elixir |
|------|-----------|--------|--------|
| File Search | via codex | `FileSearchTool` | `Codex.FileSearch` |
| Web Search | via codex | `WebSearchTool` | via codex |
| Code Interpreter | via codex | `CodeInterpreterTool` | via codex |
| Image Generation | via codex | `ImageGenerationTool` | via codex |
| Computer Control | N/A | `ComputerTool` | N/A |
| Hosted MCP | via codex | `HostedMCPTool` | N/A |
| Local Shell | via codex | `LocalShellTool` | via codex |
| Shell Tool | via codex | `ShellTool` | via codex |
| Apply Patch | N/A | `ApplyPatchTool` | N/A |

### 3.3 Tool Output Types

| Type | TypeScript | Python | Elixir |
|------|-----------|--------|--------|
| Text | string | `ToolOutputText` | `Codex.ToolOutput.Text` |
| Image | N/A | `ToolOutputImage` | `Codex.ToolOutput.Image` |
| File | N/A | `ToolOutputFileContent` | `Codex.ToolOutput.FileContent` |

---

## 4. GUARDRAILS COMPARISON

### 4.1 Input Guardrails

| Feature | Python | Elixir |
|---------|--------|--------|
| Definition | `InputGuardrail` | `Codex.Guardrail` (stage: :input) |
| Decorator | `@input_guardrail` | N/A |
| Handler Args | (context, agent, input) | (payload, context) |
| Result | `GuardrailFunctionOutput` | :ok, {:reject, msg}, {:tripwire, msg} |
| Parallel Exec | `run_in_parallel` | `run_in_parallel` |

### 4.2 Output Guardrails

| Feature | Python | Elixir |
|---------|--------|--------|
| Definition | `OutputGuardrail` | `Codex.Guardrail` (stage: :output) |
| Decorator | `@output_guardrail` | N/A |
| Handler Args | (context, agent, output) | (payload, context) |
| Result | `GuardrailFunctionOutput` | :ok, {:reject, msg}, {:tripwire, msg} |

### 4.3 Tool Guardrails

| Feature | Python | Elixir |
|---------|--------|--------|
| Input | `ToolInputGuardrail` | `Codex.ToolGuardrail` (stage: :input) |
| Output | `ToolOutputGuardrail` | `Codex.ToolGuardrail` (stage: :output) |
| Behavior | Allow/Reject/Raise | :allow, :reject_content, :raise_exception |

---

## 5. HANDOFF SYSTEM COMPARISON

| Feature | Python | Elixir |
|---------|--------|--------|
| Definition | `Handoff` | `Codex.Handoff` |
| Tool Name | `tool_name` | `tool_name` |
| Tool Desc | `tool_description` | `tool_description` |
| Input Schema | `input_json_schema` | `input_schema` |
| On Invoke | `on_invoke_handoff` | `on_invoke_handoff` |
| Agent Name | `agent_name` | `agent_name` |
| Input Filter | `input_filter` | `input_filter` |
| Nest History | `nest_handoff_history` | `nest_handoff_history` |
| Strict Schema | `strict_json_schema` | `strict_json_schema` |
| Is Enabled | `is_enabled` | `is_enabled` |
| Helper | `handoff()` function | `Handoff.wrap/2` |

### 5.1 HandoffInputData

| Field | Python | Elixir |
|-------|--------|--------|
| Input History | `input_history` | `input_history` |
| Pre-Handoff Items | `pre_handoff_items` | `pre_handoff_items` |
| New Items | `new_items` | `new_items` |
| Run Context | `run_context` | `run_context` |

---

## 6. STREAMING COMPARISON

### 6.1 Streaming Result

| Feature | TypeScript | Python | Elixir |
|---------|-----------|--------|--------|
| Class/Struct | async generator | `RunResultStreaming` | `Codex.RunResultStreaming` |
| Events Method | iteration | `stream_events()` | `events/1` |
| Raw Events | iteration | via events | `raw_events/1` |
| Pop Single | N/A | N/A | `pop/2` |
| Cancel | AbortSignal | N/A | `cancel/2` |
| Usage | via events | lazy property | `usage/1` |

### 6.2 Stream Event Types

| Event | TypeScript | Python | Elixir |
|-------|-----------|--------|--------|
| Raw Response | via events | `RawResponsesStreamEvent` | `Codex.StreamEvent.RawResponses` |
| Run Item | via events | `RunItemStreamEvent` | `Codex.StreamEvent.RunItem` |
| Agent Updated | N/A | `AgentUpdatedStreamEvent` | `Codex.StreamEvent.AgentUpdated` |
| Guardrail | N/A | N/A | `Codex.StreamEvent.GuardrailResult` |
| Tool Approval | N/A | N/A | `Codex.StreamEvent.ToolApproval` |

---

## 7. EVENT TYPES COMPARISON

### 7.1 Thread Events

| Event | TypeScript | Python | Elixir |
|-------|-----------|--------|--------|
| Thread Started | `ThreadStartedEvent` | N/A | `Codex.Events.ThreadStarted` |
| Turn Started | `TurnStartedEvent` | N/A | `Codex.Events.TurnStarted` |
| Turn Completed | `TurnCompletedEvent` | N/A | `Codex.Events.TurnCompleted` |
| Turn Failed | `TurnFailedEvent` | N/A | `Codex.Events.TurnFailed` |
| Item Started | `ItemStartedEvent` | N/A | N/A |
| Item Updated | `ItemUpdatedEvent` | N/A | N/A |
| Item Completed | `ItemCompletedEvent` | N/A | `Codex.Events.ItemCompleted` |
| Error | `ThreadErrorEvent` | N/A | N/A |

### 7.2 Elixir-Specific Events

| Event | Description |
|-------|-------------|
| `TurnContinuation` | Continuation token available |
| `ThreadTokenUsageUpdated` | Token usage delta |
| `TurnDiffUpdated` | Turn diff update |
| `TurnCompaction` | History compaction |
| `ItemAgentMessageDelta` | Message streaming |
| `ItemInputTextDelta` | Input streaming |
| `ToolCallRequested` | Tool invocation request |

---

## 8. ITEM TYPES COMPARISON

| Item | TypeScript | Python | Elixir |
|------|-----------|--------|--------|
| Agent Message | `AgentMessageItem` | `MessageOutputItem` | `Codex.Items.AgentMessage` |
| Reasoning | `ReasoningItem` | `ReasoningItem` | `Codex.Items.Reasoning` |
| Tool Call | N/A | `ToolCallItem` | N/A (via events) |
| Tool Output | N/A | `ToolCallOutputItem` | N/A (via events) |
| Handoff Call | N/A | `HandoffCallItem` | N/A (via handoff) |
| Handoff Output | N/A | `HandoffOutputItem` | N/A (via handoff) |
| Command Exec | `CommandExecutionItem` | N/A | `Codex.Items.CommandExecution` |
| File Change | `FileChangeItem` | N/A | `Codex.Items.FileChange` |
| MCP Tool Call | `McpToolCallItem` | N/A | `Codex.Items.McpToolCall` |
| Web Search | `WebSearchItem` | N/A | `Codex.Items.WebSearch` |
| Todo List | `TodoListItem` | N/A | `Codex.Items.TodoList` |
| Error | `ErrorItem` | N/A | `Codex.Items.Error` |

---

## 9. SESSION/MEMORY COMPARISON

### 9.1 Session Interface

| Method | Python | Elixir |
|--------|--------|--------|
| Load | `get_items(limit)` | `load(state)` |
| Save | `add_items(items)` | `save(state, entry)` |
| Pop | `pop_item()` | N/A |
| Clear | `clear_session()` | `clear(state)` |
| Session ID | `session_id` | via state |

### 9.2 Session Implementations

| Backend | Python | Elixir |
|---------|--------|--------|
| In-Memory | N/A | `Codex.Session.Memory` |
| SQLite | `SQLiteSession` | N/A |
| Advanced SQLite | `AdvancedSQLiteSession` | N/A |
| Redis | `RedisSession` | N/A |
| SQLAlchemy | `SQLAlchemySession` | N/A |
| Encrypted | `EncryptedSession` | N/A |
| Dapr | `DaprSession` | N/A |
| OpenAI Conversations | `OpenAIConversationsSession` | N/A |

---

## 10. MCP SUPPORT COMPARISON

### 10.1 MCP Client

| Feature | TypeScript | Python | Elixir |
|---------|-----------|--------|--------|
| Client Class | via codex | `MCPServer*` classes | `Codex.MCP.Client` |
| Handshake | via codex | automatic | `handshake/2` |
| Capabilities | via codex | automatic | `capabilities/1` |
| List Tools | via codex | `get_mcp_tools()` | `list_tools/2` |
| Call Tool | via codex | via SDK | `call_tool/4` |
| Tool Cache | via codex | N/A | yes |
| Tool Filter | via codex | `ToolFilter*` | `:allow`, `:block` opts |

### 10.2 MCP Transports

| Transport | Python | Elixir |
|-----------|--------|--------|
| Stdio | `MCPServerStdio` | via transport tuple |
| SSE | `MCPServerSse` | via transport tuple |
| HTTP | `MCPServerStreamableHttp` | via transport tuple |

---

## 11. TELEMETRY COMPARISON

### 11.1 Telemetry Events

| Event | TypeScript | Python | Elixir |
|-------|-----------|--------|--------|
| Thread Start | N/A | `AgentSpanData` | `[:codex, :thread, :start]` |
| Thread Stop | N/A | `AgentSpanData` | `[:codex, :thread, :stop]` |
| Thread Exception | N/A | `AgentSpanData` | `[:codex, :thread, :exception]` |
| Tool Start | N/A | `FunctionSpanData` | `[:codex, :tool, :start]` |
| Tool Stop | N/A | `FunctionSpanData` | `[:codex, :tool, :stop]` |
| Tool Exception | N/A | `FunctionSpanData` | `[:codex, :tool, :exception]` |
| LLM Call | N/A | `GenerationSpanData` | N/A (via thread) |
| Guardrail | N/A | `GuardrailSpanData` | N/A (via events) |
| Handoff | N/A | `HandoffSpanData` | N/A (via events) |
| Approval | N/A | N/A | `[:codex, :approval, *]` |
| Token Usage | N/A | N/A | `[:codex, :thread, :token_usage, :updated]` |
| Compaction | N/A | N/A | `[:codex, :turn, :compaction, *]` |

### 11.2 Tracing Infrastructure

| Feature | Python | Elixir |
|---------|--------|--------|
| Trace Provider | custom | OpenTelemetry |
| Span Types | 10+ custom | OTEL spans |
| Processors | `TracingProcessor` | OTEL processors |
| Export | `default_exporter` | OTLP exporter |
| Custom Spans | `custom_span()` | via OTEL API |

---

## 12. ERROR HANDLING COMPARISON

### 12.1 Exception Types

| Error | TypeScript | Python | Elixir |
|-------|-----------|--------|--------|
| Base Error | `Error` | `AgentsException` | `Codex.Error` |
| Max Turns | exit code | `MaxTurnsExceeded` | via error kind |
| Model Error | exit code | `ModelBehaviorError` | via error kind |
| User Error | exit code | `UserError` | via error kind |
| Input Guardrail | N/A | `InputGuardrailTripwireTriggered` | `Codex.GuardrailError` |
| Output Guardrail | N/A | `OutputGuardrailTripwireTriggered` | `Codex.GuardrailError` |
| Tool Input Guard | N/A | `ToolInputGuardrailTripwireTriggered` | `Codex.GuardrailError` |
| Tool Output Guard | N/A | `ToolOutputGuardrailTripwireTriggered` | `Codex.GuardrailError` |
| Approval | N/A | N/A | `Codex.ApprovalError` |
| Transport | spawn error | N/A | `Codex.TransportError` |

### 12.2 Error Classifications

| Kind | Elixir |
|------|--------|
| `:rate_limit` | Rate limit exceeded |
| `:sandbox_assessment_failed` | Sandbox check failed |
| `:unsupported_feature` | Feature not implemented |
| `:unknown` | Unknown error |

---

## 13. APPROVAL SYSTEM COMPARISON

| Feature | TypeScript | Python | Elixir |
|---------|-----------|--------|--------|
| Policy | `approvalPolicy` | N/A | `approval_policy` |
| Hook | N/A | N/A | `Codex.Approvals.Hook` |
| Static Policy | preset modes | N/A | `Codex.Approvals.StaticPolicy` |
| Async Approval | N/A | N/A | `{:async, ref}` |
| Approval Result | N/A | N/A | `:allow`, `{:deny, reason}` |
| Timeout | N/A | N/A | `approval_timeout_ms` |

---

## 14. FILE HANDLING COMPARISON

| Feature | TypeScript | Python | Elixir |
|---------|-----------|--------|--------|
| Attachments | via CLI | N/A | `Codex.Files` |
| Staging | N/A | N/A | `stage/2` |
| TTL | N/A | N/A | `:ttl_ms` option |
| Persist | N/A | N/A | `:persist` option |
| Checksum | N/A | N/A | SHA256 |
| Registry | N/A | N/A | `Codex.Files.Registry` |
| Cleanup | N/A | N/A | `prune_staging/0` |

---

## 15. REALTIME/VOICE COMPARISON

### 15.1 Realtime Audio

| Feature | Python | Elixir |
|---------|--------|--------|
| Session | `RealtimeSession` | STUB |
| Agent | `RealtimeAgent` | STUB |
| Runner | `RealtimeRunner` | STUB |
| Send Audio | `send_audio()` | STUB |
| Send Message | `send_message()` | STUB |
| Interrupt | `send_interrupt()` | STUB |
| Events | 15+ event types | STUB |
| Audio Formats | PCM16, G.711 | STUB |

### 15.2 Voice Pipeline

| Feature | Python | Elixir |
|---------|--------|--------|
| Pipeline | `VoicePipeline` | STUB |
| Config | `VoicePipelineConfig` | STUB |
| STT Model | `STTModel`, `OpenAISTTModel` | STUB |
| TTS Model | `TTSModel`, `OpenAITTSModel` | STUB |
| Audio Input | `StreamedAudioInput` | STUB |
| Audio Output | `StreamedAudioResult` | STUB |

---

## 16. HOOKS COMPARISON

| Hook | Python | Elixir |
|------|--------|--------|
| on_llm_start | yes | via hooks field (TBD) |
| on_llm_end | yes | via hooks field (TBD) |
| on_agent_start | yes | via hooks field (TBD) |
| on_agent_end | yes | via hooks field (TBD) |
| on_handoff | yes | via hooks field (TBD) |
| on_tool_start | yes | via hooks field (TBD) |
| on_tool_end | yes | via hooks field (TBD) |

---

## 17. RUN CONFIGURATION COMPARISON

| Option | Python | Elixir |
|--------|--------|--------|
| Model | `model` | `model` |
| Model Provider | `model_provider` | N/A |
| Model Settings | `model_settings` | `model_settings` |
| Max Turns | `max_turns` | `max_turns` |
| Handoff Input Filter | `handoff_input_filter` | N/A |
| Nest Handoff History | `nest_handoff_history` | `nest_handoff_history` |
| Handoff History Mapper | `handoff_history_mapper` | N/A |
| Input Guardrails | `input_guardrails` | `input_guardrails` |
| Output Guardrails | `output_guardrails` | `output_guardrails` |
| Tracing Disabled | `tracing_disabled` | `tracing_disabled` |
| Trace Sensitive | `trace_include_sensitive_data` | `trace_include_sensitive_data` |
| Workflow Name | `workflow_name` | `workflow` |
| Trace ID | `trace_id` | `trace_id` |
| Group ID | `group_id` | `group` |
| Trace Metadata | `trace_metadata` | via metadata |
| Session Callback | `session_input_callback` | `session_input_callback` |
| Model Input Filter | `call_model_input_filter` | `call_model_input_filter` |
| Session | N/A | `session` |
| Conversation ID | `conversation_id` | `conversation_id` |
| Previous Response | `previous_response_id` | `previous_response_id` |
| Auto Previous | `auto_previous_response_id` | `auto_previous_response_id` |
| Hooks | N/A | `hooks` |
| File Search | N/A | `file_search` |

---

## 18. USAGE TRACKING COMPARISON

| Feature | TypeScript | Python | Elixir |
|---------|-----------|--------|--------|
| Requests | via events | `requests` | via events |
| Input Tokens | `input_tokens` | `input_tokens` | `input_tokens` |
| Output Tokens | `output_tokens` | `output_tokens` | `output_tokens` |
| Total Tokens | computed | `total_tokens` | computed |
| Cached Tokens | `cached_input_tokens` | `input_tokens_details` | `cached_input_tokens` |
| Reasoning Tokens | N/A | `output_tokens_details` | via details |
| Per-Request | N/A | `request_usage_entries` | via events |
| Usage Merge | yes | `add()` | `merge_usage/2` |

---

This inventory provides a complete reference for identifying which features exist in each SDK and their current porting status in the Elixir implementation.
