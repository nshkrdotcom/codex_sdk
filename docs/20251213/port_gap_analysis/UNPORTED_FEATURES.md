# Codex SDK Elixir Port - Gap Analysis

**Date**: 2025-12-13
**Analysis**: Comparison of TypeScript codex/ and Python openai-agents-python/ against Elixir codex_sdk/

## Executive Summary

The original estimate (**~85–90%**) overstated parity. The Elixir SDK covers the core agent loop well,
and it now forwards the main Codex CLI knobs used by the TypeScript SDK (sandbox/cd/add-dir/skip-git,
base URL, network access, web search, approval policy). Remaining gaps are concentrated in Python
realtime/voice and in “Python-style” execution knobs that don’t map cleanly to the Codex CLI.

---

## 1. FROM CODEX (TypeScript SDK)

### 1.1 FULLY PORTED / PARTIAL

| Feature | TypeScript | Elixir | Status |
|---------|-----------|--------|--------|
| Core Codex class | `Codex` | `Codex` | DONE |
| Thread management | `Thread` | `Codex.Thread` | DONE |
| Streaming execution | `runStreamed()` | `run_streamed/3` | DONE |
| CodexOptions | `apiKey`, `baseUrl`, `codexPathOverride`, `env` | `Codex.Options` | PARTIAL (no “replace entire env” mode like TS; base URL is forwarded via `OPENAI_BASE_URL`) |
| ThreadOptions | model/sandbox/cd/add-dir/skip-git/network/web_search/approval_policy | `Codex.Thread.Options` | DONE (forwarded to `codex exec` via flags/`--config` where applicable) |
| TurnOptions | output schema + AbortSignal | `turn_opts` | PARTIAL (output schema supported; cancellation differs) |
| Event types | 8 event types | `Codex.Events.*` | DONE (+ Elixir adds extra event structs) |
| Item types | All item types | `Codex.Items.*` | DONE |
| MCP support | MCP tool calls | `Codex.MCP.Client` | DONE |
| Structured output | JSON schema | Supported | DONE |
| Process execution | spawn/readline | erlexec | DONE |
| Platform/binary resolution | bundled vendor binary | `Options.codex_path/1` | PARTIAL (no bundled binary; uses `CODEX_PATH`/PATH) |
| Abort/cancellation | `AbortSignal` | cancellation token + stream cancel | PARTIAL |

### 1.2 NOT PORTED / GAPS

#### 1.2.1 Shell Tool MCP (codex/shell-tool-mcp)

**Missing**: The full `shell-tool-mcp` server implementation is not ported.

```typescript
// TypeScript has:
- bashSelection.ts - Platform-specific bash variant selection
- osRelease.ts + bashSelection.ts - Linux distro/version detection for bash selection (Ubuntu/Debian/CentOS/RHEL-family)
- execve wrapper support for sandboxing
- Version-aware bash selection for different OS versions
```

**Elixir Status**: The Elixir SDK relies on the codex binary for shell execution rather than implementing its own MCP server. This is acceptable but limits standalone MCP server capability.

**Recommendation**: LOW priority - The current approach works well.

---

#### 1.2.2 Image Input Handling

**Missing**: TypeScript-style typed “mixed input” (`UserInput[]`) that can inline local images per turn.

```typescript
// TypeScript supports:
type UserInput =
  | { type: "text"; text: string }
  | { type: "local_image"; path: string };
```

**Elixir Status**: Image passing is supported via `Codex.Files` staging + `Thread.Options.attachments`
(translated to `codex exec --image ...`), but there is no `UserInput[]`-style API.

**Recommendation**: MEDIUM priority - Add explicit image input type.

```elixir
# Proposed addition to Codex.Thread:
@type user_input :: String.t() | %{type: :text, text: String.t()} | %{type: :local_image, path: String.t()}
```

---

#### 1.2.3 Sandbox Mode Constants

**Missing**: Nothing (forwarding + mapping implemented). Remaining work is documentation polish only.

```typescript
// TypeScript:
type SandboxMode = "read-only" | "workspace-write" | "danger-full-access";
```

**Elixir Status**: Forwarded to `codex exec --sandbox ...` with a default mapping:
`:strict → read-only`, `:default → workspace-write`, `:permissive → danger-full-access`.

**Recommendation**: DONE (mapping + forwarding implemented). Remaining work is documentation polish only.

---

## 2. FROM OPENAI-AGENTS-PYTHON

### 2.1 FULLY PORTED

| Feature | Python | Elixir | Status |
|---------|--------|--------|--------|
| Agent class | `Agent` | `Codex.Agent` | DONE |
| Tool system | `FunctionTool` | `Codex.FunctionTool` | DONE |
| Handoffs | `Handoff` | `Codex.Handoff` | DONE |
| Guardrails | Input/Output | `Codex.Guardrail` | DONE |
| Tool guardrails | Tool-specific | `Codex.ToolGuardrail` | DONE |
| Run config | `RunConfig` | `Codex.RunConfig` | DONE |
| Model settings | `ModelSettings` | `Codex.ModelSettings` | PARTIAL (struct exists; not forwarded to `codex exec`) |
| Streaming | `RunResultStreaming` | `Codex.RunResultStreaming` | DONE |
| Session | `Session` protocol | `Codex.Session` behavior | DONE |
| Session implementations | `SQLiteSession` (+ extensions) | `Codex.Session.Memory` | PARTIAL (Elixir has in-memory only; no SQLite/Redis/etc) |
| Telemetry | Tracing spans | `Codex.Telemetry` + OTEL | DONE |
| Tool output types | Text/Image/File | `Codex.ToolOutput` | DONE |
| Usage tracking | `Usage` class | Via events + result | DONE |
| Exception hierarchy | 5+ exception types | `Codex.Error.*` | DONE |
| MCP integration | `MCPServer*` | `Codex.MCP.Client` | DONE |

### 2.2 NOT PORTED / GAPS

#### 2.2.1 REALTIME AUDIO/VOICE (HIGH PRIORITY GAP)

**Missing**: Full realtime WebSocket audio streaming.

```python
# Python has extensive realtime support:
class RealtimeAgent:
    """Audio-optimized agent variant"""

class RealtimeSession:
    """WebSocket connection management"""
    async def send_audio(audio: bytes)
    async def send_message(text: str)
    async def send_interrupt()

# Event types:
RealtimeAudio, RealtimeAudioEnd, RealtimeAudioInterrupted
RealtimeToolStart, RealtimeToolEnd
RealtimeHandoffEvent, RealtimeAgentStartEvent
RealtimeHistoryAdded, RealtimeHistoryUpdated
```

**Elixir Status**: Stub only - returns `{:error, :unsupported_feature}`

**Recommendation**: HIGH priority if realtime is needed. Requires:
- WebSocket client (e.g., `WebSockex` or `Mint.WebSocket`)
- Audio format handling (PCM16, G.711)
- Turn detection configuration
- Realtime event types

---

#### 2.2.2 VOICE PIPELINE (HIGH PRIORITY GAP)

**Missing**: Non-realtime voice pipeline (STT → Agent → TTS).

```python
# Python has:
class VoicePipeline:
    """Audio processing pipeline"""

class VoicePipelineConfig:
    stt_model: STTModel
    tts_model: TTSModel

class STTModel / OpenAISTTModel:
    """Speech-to-text interface"""

class TTSModel / OpenAITTSModel:
    """Text-to-speech interface"""

class StreamedAudioResult:
    """Async audio output stream"""
```

**Elixir Status**: Stub only - returns `{:error, :unsupported_feature}`

**Recommendation**: MEDIUM-HIGH priority. Requires:
- OpenAI Whisper API integration
- OpenAI TTS API integration
- Audio streaming infrastructure

---

#### 2.2.3 MULTIPLE SESSION BACKENDS

**Missing**: Alternative session storage implementations.

```python
# Python has:
class SQLiteSession:       # File-based SQLite
class AdvancedSQLiteSession:  # Enhanced SQLite
class RedisSession:        # Redis backend (requires redis extra)
class SQLAlchemySession:   # ORM-based (requires sqlalchemy extra)
class EncryptedSession:    # Encrypted wrapper (requires encrypt extra)
class DaprSession:         # Dapr state store (requires dapr extra)
class OpenAIConversationsSession:  # Server-side storage
```

**Elixir Status**: Only `Codex.Session.Memory` (in-memory Agent) implemented.

**Recommendation**: MEDIUM priority. Add:
- `Codex.Session.ETS` - ETS-backed persistent session
- `Codex.Session.DETS` - DETS file-backed session
- `Codex.Session.Mnesia` - Distributed session
- `Codex.Session.Redis` - Redis adapter (optional dep)
- `Codex.Session.Ecto` - Ecto/database adapter (optional dep)

---

#### 2.2.4 LITELLM / MULTI-PROVIDER MODEL SUPPORT

**Missing**: Alternative model providers beyond OpenAI.

```python
# Python has:
class LitellmProvider:
    """100+ model support via LiteLLM"""

class MultiProvider:
    """Provider aggregation with fallback"""
```

**Elixir Status**: Only OpenAI models via codex binary.

**Recommendation**: LOW priority - codex binary handles this. But for standalone use, could add:
- `Codex.Models.Provider` behavior
- `Codex.Models.OpenAI` implementation
- `Codex.Models.Anthropic` implementation (optional)

---

#### 2.2.5 HOSTED TOOLS (PARTIAL)

**Missing**: Concrete implementations matching Python’s behavior (not just wrappers).

```python
# Python has these hosted tools:
FileSearchTool      # Vector store search
WebSearchTool       # Web search
ComputerTool        # Computer/browser control
HostedMCPTool       # Remote MCP execution
CodeInterpreterTool # Sandboxed code execution
ImageGenerationTool # DALL-E integration
LocalShellTool      # Local shell execution
ShellTool           # Modern shell tool
ApplyPatchTool      # File mutation via diffs
```

**Elixir Status**:
- Wrapper modules exist under `lib/codex/tools/hosted_tools.ex`:
  `Codex.Tools.{FileSearchTool,WebSearchTool,ComputerTool,HostedMcpTool,CodeInterpreterTool,ImageGenerationTool,ShellTool,ApplyPatchTool}`.
- These wrappers are callback-driven; they do not implement browser automation, diff application, etc. out of the box.

**Recommendation**: MEDIUM priority. Implement missing *engines* behind the wrappers:
- ApplyPatch: parse/apply diffs (Python has `apply_diff` + `ApplyPatchEditor` operations)
- Computer: provide an implementation (Python has `Computer`/`AsyncComputer`)
- Web/File search: provide default implementations (or clearly document “bring your own callback”)

---

#### 2.2.6 COMPUTER INTERFACE

**Missing**: Computer/browser automation interface.

```python
# Python has:
class Computer:
    environment: Literal["mac", "windows", "ubuntu", "browser"]
    dimensions: tuple[int, int]

    def screenshot() -> str
    def click(x, y, button)
    def double_click(x, y)
    def scroll(x, y, scroll_x, scroll_y)
    def type(text: str)
    def wait()
    def move(x, y)
    def keypress(keys)
    def drag(path)

class AsyncComputer:
    """Async variant of Computer"""
```

**Elixir Status**: Wrapper exists (`Codex.Tools.ComputerTool`) but there is no built-in computer automation implementation equivalent to Python’s `Computer` / `AsyncComputer`.

**Recommendation**: LOW priority unless computer-use is needed. Could add:
- `Codex.Computer` behavior
- `Codex.Computer.Browser` - Browser automation via ChromeDriver/Playwright

---

#### 2.2.7 APPLY PATCH / EDITOR INTERFACE

**Missing**: Unified diff-based file editing.

```python
# Python has:
class ApplyPatchTool:
    """File mutation via unified diffs"""
    editor: ApplyPatchEditor

class ApplyPatchEditor(Protocol):
    def create_file(op: CreateFileOperation) -> ApplyPatchResult
    def update_file(op: UpdateFileOperation) -> ApplyPatchResult
    def delete_file(op: DeleteFileOperation) -> ApplyPatchResult
```

**Elixir Status**: Wrapper exists (`Codex.Tools.ApplyPatchTool`) but there is no built-in diff parser/applicator.

**Recommendation**: MEDIUM priority. Add:
- `Codex.Tools.ApplyPatch` - Diff application tool
- `Codex.Editor` behavior for customization

---

#### 2.2.8 LIFECYCLE HOOKS (PARTIAL)

**Missing**: Some hook callbacks not exposed.

```python
# Python has:
class RunHooks:
    on_llm_start(context, agent, system_prompt, input_items)
    on_llm_end(context, agent, response)
    on_agent_start(context, agent)
    on_agent_end(context, agent, output)
    on_handoff(context, from_agent, to_agent)
    on_tool_start(context, agent, tool)
    on_tool_end(context, agent, tool, result)

class AgentHooks:
    on_start()
    on_end()
    on_handoff()
    on_tool_start()
    on_tool_end()
```

**Elixir Status**: `Codex.Agent` and `Codex.RunConfig` have `hooks` fields, but they are not invoked in the current runner implementation.

**Recommendation**: MEDIUM priority. Define:
- `Codex.Hooks` behavior with all callbacks
- `Codex.Agent.Hooks` for agent-specific hooks

---

#### 2.2.9 DYNAMIC PROMPTS

**Missing**: Runtime prompt configuration from OpenAI Prompts API.

```python
# Python has:
class Prompt(TypedDict):
    id: str
    version: str | None
    variables: dict | None

DynamicPromptFunction = Callable[[GenerateDynamicPromptData], Prompt | Awaitable[Prompt]]
```

**Elixir Status**: Agent has `prompt` field but not OpenAI Prompts API integration.

**Recommendation**: LOW priority - requires OpenAI Prompts API access.

---

#### 2.2.10 EXTENDED THINKING / REASONING OUTPUT CONTROL

**Missing**: Reasoning effort configuration and output control.

```python
# Python has:
ModelSettings.reasoning = {...}  # Extended thinking config
ReasoningItem  # Structured reasoning output

# Reasoning efforts:
"minimal", "low", "medium", "high"
```

**Elixir Status**: PARTIAL - `Codex.Options.reasoning_effort` is forwarded to `codex exec` via `--config model_reasoning_effort=...`, but `Codex.ModelSettings` is not forwarded to the CLI today.

**Recommendation**: LOW priority - works through codex binary.

---

#### 2.2.11 RESPONSE CHAINING

**Missing**: Explicit response chaining via `previous_response_id`.

```python
# Python has:
RunConfig.previous_response_id  # Skip redundant input
RunConfig.auto_previous_response_id  # Auto-enable
```

**Elixir Status**: Codex CLI does not expose `codex exec` flags for user-supplied response chaining.
The supported “continue” mechanism is `thread_id` + `resume` (which Elixir supports).

**Recommendation**: Treat `previous_response_id` / `conversation_id` as Python-compat metadata only; use `resume` for Codex CLI continuation.

---

#### 2.2.12 CONVERSATION STATE API

**Missing**: OpenAI Conversations API integration.

```python
# Python has:
class OpenAIConversationsSession:
    """Server-side conversation storage"""
    conversation_id: str

RunConfig.conversation_id  # Server-side storage
```

**Elixir Status**: Codex CLI session continuation is performed via `resume` rather than user-supplied conversation ids in `codex exec`.

**Recommendation**: LOW priority unless/until the `codex` CLI exposes an explicit conversation-id interface.

---

#### 2.2.13 TRACE PROCESSOR EXTENSIBILITY

**Missing**: Custom trace processor registration.

```python
# Python has:
TracingProcessor  # Interface for trace consumers
add_trace_processor(processor)
set_trace_processors(processors)
set_trace_provider(provider)

# Span types:
AgentSpanData, FunctionSpanData, GenerationSpanData
GuardrailSpanData, HandoffSpanData, CustomSpanData
SpeechSpanData, TranscriptionSpanData, MCPListToolsSpanData
```

**Elixir Status**: Uses OpenTelemetry directly - different approach.

**Recommendation**: LOW priority - OpenTelemetry is more standard in Elixir.

---

#### 2.2.14 DOCSTRING PARSING FOR TOOL SCHEMAS

**Missing**: Automatic docstring-to-schema conversion.

```python
# Python has:
@function_tool
def my_tool(x: int, y: str) -> str:
    """
    Description here.

    Args:
        x: The first parameter
        y: The second parameter
    """

# Auto-generates JSON schema from signature + docstring
DocstringStyle: google, numpy, sphinx
```

**Elixir Status**: Uses explicit parameter map in `FunctionTool` macro.

**Recommendation**: LOW priority - Elixir's approach is more explicit and type-safe.

---

#### 2.2.15 REPL / DEMO UTILITIES

**Missing**: Interactive demo loop for testing.

```python
# Python has:
async def run_demo_loop(
    agent: Agent,
    *,
    stream: bool = True,
    max_turns: int = 1000000
):
    """Interactive CLI demo"""
```

**Elixir Status**: Examples provide similar functionality but no `run_demo_loop/2` equivalent.

**Recommendation**: LOW priority - examples serve this purpose.

---

## 3. SUMMARY: PRIORITY RANKING

### HIGH PRIORITY (Should Implement)

| Feature | Source | Effort | Impact |
|---------|--------|--------|--------|
| Realtime Audio | Python | HIGH | Enables voice agents |
| Voice Pipeline | Python | MEDIUM | Enables audio I/O |

### MEDIUM PRIORITY (Nice to Have)

| Feature | Source | Effort | Impact |
|---------|--------|--------|--------|
| Additional Session Backends | Python | MEDIUM | Production persistence |
| Image Input Type | TypeScript | LOW | Better API ergonomics |
| Lifecycle Hooks | Python | MEDIUM | Better extensibility |
| Hosted Tool Wrappers | Python | MEDIUM | Convenience APIs |
| ApplyPatch Tool | Python | LOW | File editing capability |

### LOW PRIORITY (Optional)

| Feature | Source | Effort | Impact |
|---------|--------|--------|--------|
| Shell Tool MCP | TypeScript | HIGH | Standalone MCP server |
| LiteLLM Provider | Python | MEDIUM | Multi-provider support |
| Computer Interface | Python | HIGH | Browser automation |
| Dynamic Prompts | Python | LOW | OpenAI-specific feature |
| REPL Utilities | Python | LOW | Developer convenience |

---

## 4. FEATURE PARITY MATRIX

```
                           TypeScript    Python    Elixir
Core Agent System               Y           Y         Y
Thread Management               Y           -         Y
Tool System                     Y           Y         Y
Guardrails                      -           Y         Y
Handoffs                        -           Y         Y
MCP Support                     Y           Y         Y
Streaming                       Y           Y         Y
Session Persistence             -           Y         PARTIAL
Telemetry/Tracing               -           Y         Y (OTEL)
Structured Output               Y           Y         Y
File Attachments                Y           -         Y
File Search                     Y           Y         Y
Realtime Audio                  -           Y         STUB
Voice Pipeline                  -           Y         STUB
Multi-Provider Models           -           Y         -
Computer Control                -           Y         -
Response Chaining               -           Y         PARTIAL (metadata-only)
Conversation State API          -           Y         PARTIAL (metadata-only)
```

---

## 5. RECOMMENDATIONS

### Immediate Actions
1. **DONE**: TypeScript-style `ThreadOptions` forwarding (sandbox/cd/add-dir/skip-git/network/web_search/approval_policy + `OPENAI_BASE_URL`)
2. **Document** that Codex CLI continuation is `thread_id` + `resume` (not `previous_response_id`)
3. **Optionally add** a typed “local image” input API (Elixir already supports `--image` via attachments)

### Short-Term (Next Release)
1. **Implement** at least one persistent session backend (ETS or DETS)
2. **Define + wire** lifecycle hooks (Python’s `RunHooks`/`AgentHooks` equivalents; Elixir fields exist but are unused)
3. **Ship defaults or document BYO** for hosted tools (wrappers exist; engines are missing)

### Medium-Term (Future Releases)
1. **Evaluate** realtime/voice requirements - implement if needed
2. **Consider** adding Redis/Ecto session adapters
3. **Implement** diff parsing/application (Python has `apply_diff` + structured patch operations)

---

## 6. CONCLUSION

The Elixir Codex SDK is strong for text workflows, but parity is **uneven** across sources:
- The Python agent loop concepts are largely present (tools/guardrails/handoffs/sessions/streaming), with notable gaps in lifecycle hooks and realtime/voice.
- The TypeScript SDK is a thin wrapper around Codex CLI flags/env; Elixir now forwards the same major knobs.

The main gaps to close are:

1. **Realtime/Voice** - Intentionally stubbed; implement when needed
2. **Codex CLI option forwarding** - DONE
3. **Session backends** - Only in-memory; add persistent options
4. **Lifecycle hooks** - Fields exist; callbacks are not invoked today
5. **Hosted tool engines** - Wrappers exist; implementations (computer automation, diff application, etc.) are BYO

The SDK is production-ready for text-based agent workflows when the “bring your own hosted tool implementation” model is acceptable.

---

## Review Notes

- Date: 2025-12-14
- Summary: Corrected overstated “fully ported” claims and implemented Codex CLI option forwarding in Elixir (`OPENAI_BASE_URL`, `--sandbox`, `--cd`, `--add-dir`, `--skip-git-repo-check`, plus `--config` for `approval_policy`, `features.web_search_request`, and `sandbox_workspace_write.network_access`) to match the TypeScript SDK’s behavior. Added an optional `clear_env?` execution switch to harden subprocess environment handling.
- Confidence: High (forwarding verified against `codex exec --help`; environment semantics verified against erlexec docs/source).
