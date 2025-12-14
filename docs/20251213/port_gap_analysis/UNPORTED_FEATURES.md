# Codex SDK Elixir Port - Gap Analysis

**Date**: 2025-12-13
**Analysis**: Comparison of TypeScript codex/ and Python openai-agents-python/ against Elixir codex_sdk/

## Executive Summary

The Elixir SDK has successfully ported **~85-90%** of features from both source SDKs. This document identifies the remaining **unported features** that could be added to achieve full feature parity.

---

## 1. FROM CODEX (TypeScript SDK)

### 1.1 FULLY PORTED

| Feature | TypeScript | Elixir | Status |
|---------|-----------|--------|--------|
| Core Codex class | `Codex` | `Codex` | DONE |
| Thread management | `Thread` | `Codex.Thread` | DONE |
| Streaming execution | `runStreamed()` | `run_streamed/3` | DONE |
| CodexOptions | Full options | `Codex.Options` | DONE |
| ThreadOptions | All options | `Codex.Thread.Options` | DONE |
| TurnOptions | Output schema | Supported via turn_opts | DONE |
| Event types | 10+ event types | `Codex.Events.*` | DONE |
| Item types | All item types | `Codex.Items.*` | DONE |
| MCP support | MCP tool calls | `Codex.MCP.Client` | DONE |
| Structured output | JSON schema | Supported | DONE |
| Process execution | spawn/readline | erlexec | DONE |
| Platform detection | Binary resolution | Via codex_path | DONE |
| Abort/cancellation | AbortSignal | cancel/2 modes | DONE |

### 1.2 NOT PORTED / GAPS

#### 1.2.1 Shell Tool MCP (codex/shell-tool-mcp)

**Missing**: The full `shell-tool-mcp` server implementation is not ported.

```typescript
// TypeScript has:
- bashSelection.ts - Platform-specific bash variant selection
- platform.ts - Linux distro detection (Ubuntu, Debian, RHEL, Alpine, etc.)
- execve wrapper support for sandboxing
- Version-aware bash selection for different OS versions
```

**Elixir Status**: The Elixir SDK relies on the codex binary for shell execution rather than implementing its own MCP server. This is acceptable but limits standalone MCP server capability.

**Recommendation**: LOW priority - The current approach works well.

---

#### 1.2.2 Image Input Handling

**Missing**: Direct local image file support in inputs.

```typescript
// TypeScript supports:
type UserInput =
  | { type: "text"; text: string }
  | { type: "local_image"; path: string };
```

**Elixir Status**: Not directly exposed - images go through attachments.

**Recommendation**: MEDIUM priority - Add explicit image input type.

```elixir
# Proposed addition to Codex.Thread:
@type user_input :: String.t() | %{type: :text, text: String.t()} | %{type: :local_image, path: String.t()}
```

---

#### 1.2.3 Sandbox Mode Constants

**Missing**: Explicit sandbox mode type with all values documented.

```typescript
// TypeScript:
type SandboxMode = "read-only" | "workspace-write" | "danger-full-access";
```

**Elixir Status**: Uses atoms `:default`, `:strict`, `:permissive` - different naming.

**Recommendation**: LOW priority - Document the mapping or add aliases.

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
| Model settings | `ModelSettings` | `Codex.ModelSettings` | DONE |
| Streaming | `RunResultStreaming` | `Codex.RunResultStreaming` | DONE |
| Session | `Session` protocol | `Codex.Session` behavior | DONE |
| Memory session | `SQLiteSession` | `Codex.Session.Memory` | PARTIAL |
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
class LiteLLMProvider:
    """100+ model support via LiteLLM"""

class LiteLLMModel:
    """LiteLLM model wrapper"""

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

**Missing**: Some hosted tool types not fully implemented.

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
- FileSearch: DONE via `Codex.FileSearch`
- WebSearch: Available via codex binary
- Others: Not explicitly implemented as standalone tools

**Recommendation**: MEDIUM priority. Add explicit wrappers for:
- `Codex.Tools.WebSearch`
- `Codex.Tools.CodeInterpreter`
- `Codex.Tools.ImageGeneration`
- `Codex.Tools.Computer`
- `Codex.Tools.ApplyPatch`

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

**Elixir Status**: Not implemented.

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

**Elixir Status**: Not implemented as standalone tool.

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

**Elixir Status**: `hooks` field exists in Agent but callback structure not fully defined.

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

**Elixir Status**: PARTIAL - `Codex.Models.reasoning_efforts()` exists but not full integration.

**Recommendation**: LOW priority - works through codex binary.

---

#### 2.2.11 RESPONSE CHAINING

**Missing**: Explicit response chaining via `previous_response_id`.

```python
# Python has:
RunConfig.previous_response_id  # Skip redundant input
RunConfig.auto_previous_response_id  # Auto-enable
```

**Elixir Status**: `Codex.RunConfig.previous_response_id` exists - may need verification.

**Recommendation**: Verify this is working correctly in Elixir.

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

**Elixir Status**: `Codex.RunConfig.conversation_id` field exists but integration unclear.

**Recommendation**: LOW priority - verify integration with codex binary.

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
Response Chaining               -           Y         Y
Conversation State API          -           Y         PARTIAL
```

---

## 5. RECOMMENDATIONS

### Immediate Actions
1. **Verify** response chaining and conversation_id work correctly
2. **Document** the sandbox mode mapping (`:default`/`:strict`/`:permissive` ↔ sandbox modes)
3. **Add** explicit image input type for better ergonomics

### Short-Term (Next Release)
1. **Implement** at least one persistent session backend (ETS or DETS)
2. **Define** the `Codex.Hooks` behavior formally
3. **Add** convenience wrappers for hosted tools

### Medium-Term (Future Releases)
1. **Evaluate** realtime/voice requirements - implement if needed
2. **Consider** adding Redis/Ecto session adapters
3. **Add** ApplyPatch tool for file editing workflows

---

## 6. CONCLUSION

The Elixir Codex SDK has achieved excellent feature parity with both source SDKs. The main gaps are:

1. **Realtime/Voice** - Intentionally stubbed; implement when needed
2. **Session backends** - Only in-memory; add persistent options
3. **Some convenience APIs** - Hosted tool wrappers, hooks, etc.

The SDK is production-ready for all text-based agent workflows. Audio/voice capabilities require additional implementation if needed for specific use cases.
