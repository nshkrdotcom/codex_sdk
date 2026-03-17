# Subagents and Multi-Agent Workflows

This guide explains how upstream Codex subagents work in the vendored
`./codex/codex-rs` tree and maps that behavior onto the current Elixir SDK.

It is based on the vendored `codex-rs` snapshot in this repository, not on a
separate external release stream.

It is intentionally explicit about the gap:

- upstream Codex has an experimental multi-agent system
- `codex_sdk` does not yet provide first-class Elixir APIs for it
- the SDK currently exposes only partial, transport-level observability

## Status at a Glance

| Area | Upstream `codex-rs` | `codex_sdk` today |
| --- | --- | --- |
| Feature flag | `features.multi_agent` enables the collaboration tool surface | No SDK helper; this is controlled by the underlying Codex runtime |
| Agent orchestration tools | `spawn_agent`, `send_input`, `resume_agent`, `wait`, `close_agent` | Not exposed as Elixir APIs |
| Agent roles | Built-in roles plus user-defined roles in `config.toml` | No Elixir role-management API |
| Limits and depth | `agents.max_threads`, `agents.max_depth`, `agents.job_max_runtime_seconds` | No Elixir abstraction over these settings |
| Thread metadata | Subagent thread sources plus `agentNickname` and `agentRole` | Available through app-server thread APIs |
| Streaming visibility | Collab tool-call items and lifecycle events | Partially normalized in `Codex.Items` and `Codex.Events` |

## What "Subagents" Means Upstream

In upstream Codex, "subagents" are child agent threads spawned by an active
agent during a turn. The parent agent delegates a bounded task, keeps working,
and later waits for or reuses the child.

Upstream naming is slightly inconsistent, so it helps to treat these as aliases:

- `features.multi_agent`: config flag name
- "Multi-agents": TUI / experimental-feature label
- "subagent": runtime concept
- `subAgentThreadSpawn`: app-server thread source kind for spawned child threads

This is different from two other concepts already present in this SDK:

- `collaboration_mode`: a single-agent prompt preset such as `:plan` or
  `:pair_programming`
- `approvals_reviewer: :guardian_subagent`: approval-routing behavior for
  escalated reviews, not general subagent orchestration
- manual concurrency: you starting multiple `Codex` threads from Elixir and
  coordinating them yourself

Those are useful, but they are not upstream subagent orchestration.

## How Upstream Subagents Work

### 1. The feature is gated

Upstream ships subagents behind the experimental `multi_agent` feature flag.
The TUI exposes it as "Multi-agents" and prompts the user to enable it through
`/experimental`, with the change taking effect on the next session.

Example upstream config:

```toml
[features]
multi_agent = true
```

### 2. The parent agent gets a collaboration tool surface

When the feature is enabled, upstream can expose these tools to the active
agent:

| Tool | Purpose |
| --- | --- |
| `spawn_agent` | Create a child agent thread for a scoped task |
| `send_input` | Send follow-up input to an existing child |
| `resume_agent` | Reopen a previously closed child thread |
| `wait` | Wait for one or more child agents to reach a final state |
| `close_agent` | Shut down a child agent when it is no longer needed |

Related but separate: upstream also has `spawn_agents_on_csv` for fanout job
execution. That is adjacent to subagents, but it is not the core subagent
feature.

### 3. Spawned agents are real threads

The returned `agent_id` is effectively a thread id. A spawned child becomes its
own thread with subagent-specific metadata, status, and history.

Upstream records the child session source as a subagent source. For spawned
threads that means:

- parent thread id
- nesting depth
- optional agent nickname
- optional agent role

Upstream also uses subagent source tags for non-spawn cases such as review,
compaction, and memory consolidation.

### 4. Children inherit the live runtime state

This is one of the most important design details.

Upstream does not spawn children from a cold default config. A child starts
from the parent turn's effective runtime state, including:

- model and provider
- reasoning effort
- developer instructions
- working directory
- sandbox policy
- approval policy
- shell environment policy

After inheritance, upstream may apply:

- an agent role layer
- explicit `model` / `reasoning_effort` overrides from `spawn_agent`
- depth-based feature restrictions

This matters because it keeps the child aligned with the parent's real
execution environment instead of silently drifting to unrelated defaults.

### 5. Roles are config layers

Upstream supports built-in and user-defined agent roles.

Built-in roles:

- `default`
- `explorer`
- `worker`

User-defined roles live under `[agents.<role_name>]` and can declare:

- `description`
- `config_file`
- `nickname_candidates`

Relative `config_file` paths are resolved relative to the `config.toml` that
declares the role.

Example upstream config:

```toml
[features]
multi_agent = true

[agents]
max_threads = 6
max_depth = 1

[agents.researcher]
description = "Read-heavy repo exploration"
config_file = "/absolute/path/to/researcher.toml"
nickname_candidates = ["Atlas", "Juniper"]
```

Role config files are merged as high-precedence config layers. A role may pin a
model or reasoning effort, in which case upstream treats those settings as
locked for that role.

### 6. Depth and thread limits are enforced

Upstream defaults matter here:

- `agents.max_threads` defaults to `6`
- `agents.max_depth` defaults to `1`
- root sessions start at depth `0`

With the default depth of `1`, a root agent may spawn children, but those
children cannot keep spawning deeper generations. Upstream allows the child at
the maximum depth to exist, then disables further collaboration/fanout tools in
that child.

### 7. Waiting is intentionally coarse-grained

The upstream `wait` tool is designed to avoid hot polling:

- default timeout: `30_000` ms
- minimum timeout: `10_000` ms
- maximum timeout: `3_600_000` ms
- when multiple ids are passed, it waits for the first one to reach a final
  status

That behavior is deliberate. Upstream is trying to keep the orchestrator from
burning CPU in tight wait loops.

## Protocol and Transport Surfaces

Subagents are not only a prompt-level behavior. They show up in transport and
API surfaces too.

### App-server thread metadata

Upstream app-server threads can carry:

- subagent source kinds such as `subAgentThreadSpawn`
- `agentNickname`
- `agentRole`

Relevant source kinds include:

- `subAgent`
- `subAgentReview`
- `subAgentCompact`
- `subAgentThreadSpawn`
- `subAgentOther`

### App-server items

Upstream app-server exposes `collabToolCall` items for collaboration activity.
Those items describe actions such as:

- `spawn_agent`
- `send_input`
- `resume_agent`
- `wait`
- `close_agent`

### Additional lifecycle events

The vendored upstream runtime also emits dedicated collaboration lifecycle
events such as spawn, interaction, waiting, close, and resume begin/end events.

### Responses API header tagging

When upstream makes Responses API requests from a subagent context, it adds an
`x-openai-subagent` header. The vendored code maps sources to values such as:

- `review`
- `compact`
- `memory_consolidation`
- `collab_spawn`
- a custom label for `Other(...)`

That header is an implementation detail, but it is part of how upstream keeps
subagent traffic distinguishable end to end.

## What the Elixir SDK Supports Today

This SDK currently has passive support, not active orchestration support.

### What exists

- `Codex.AppServer.thread_list/2` can filter by subagent-related `source_kinds`
- `Codex.AppServer.thread_read/3` can read stored subagent threads
- app-server item normalization includes `Codex.Items.CollabAgentToolCall`
- event normalization includes collab lifecycle event structs such as:
  `Codex.Events.CollabAgentSpawnBegin`,
  `Codex.Events.CollabAgentSpawnEnd`,
  `Codex.Events.CollabAgentInteractionBegin`,
  `Codex.Events.CollabAgentInteractionEnd`,
  `Codex.Events.CollabWaitingBegin`,
  `Codex.Events.CollabWaitingEnd`,
  `Codex.Events.CollabCloseBegin`,
  `Codex.Events.CollabCloseEnd`
- `Codex.Protocol.CollaborationMode` exists, but that is a separate feature

### What does not exist

- no `Codex.Subagents` module
- no Elixir wrappers for `spawn_agent`, `send_input`, `resume_agent`, `wait`,
  or `close_agent`
- no typed Elixir API for agent ids, nicknames, roles, or parent/child routing
- no first-class config helpers for `features.multi_agent` or `[agents.*]`
- no complete parity guarantee for the full upstream collaboration event surface
- no high-level examples showing true upstream subagent orchestration from
  Elixir

That is why this guide should be read as:

- a product and architecture guide for the feature
- a gap map for this repository
- not a claim that subagents are already supported end to end in Elixir

## What You Can Do Right Now from Elixir

### Observe upstream subagent threads

If you are connected to `codex app-server`, you can inspect stored or active
subagent threads:

```elixir
{:ok, %{"data" => threads}} =
  Codex.AppServer.thread_list(conn,
    source_kinds: [:sub_agent_thread_spawn, :sub_agent_review]
  )

Enum.each(threads, fn thread ->
  IO.inspect(%{
    id: thread["id"],
    source: thread["source"],
    nickname: thread["agentNickname"],
    role: thread["agentRole"]
  })
end)
```

### Observe collaboration activity in streamed events

When the upstream runtime emits collaboration items or lifecycle events, this
SDK can surface them in streamed turn output.

```elixir
{:ok, stream} = Codex.Thread.run_streamed(thread, "Work on this task")

for event <- stream do
  case event do
    %Codex.Events.ItemCompleted{
      item: %Codex.Items.CollabAgentToolCall{} = item
    } ->
      IO.inspect({:collab_item, item.tool, item.status, item.receiver_thread_ids})

    %Codex.Events.CollabAgentSpawnBegin{} = item ->
      IO.inspect({:spawn_begin, item.call_id, item.prompt})

    %Codex.Events.CollabWaitingEnd{} = item ->
      IO.inspect({:wait_end, item.call_id, item.statuses})

    _ ->
      :ok
  end
end
```

### Build manual multi-thread workflows

If you want concurrent work today, the supported Elixir approach is still manual
orchestration:

1. start multiple `Codex` threads yourself
2. run work in parallel under your own supervision
3. merge or synthesize results in Elixir

That is useful, but it should not be described as upstream subagent support.

## Recommended Documentation Position for This Repo

For this repository, the most accurate positioning is:

- upstream Codex supports subagents
- this SDK can observe parts of that behavior
- this SDK does not yet expose first-class subagent control

In other words, subagents are a documented upstream feature and a known SDK gap.

## What First-Class Elixir Support Would Need

A real Elixir integration would need more than event parsing. At minimum it
would need:

- public wrappers for `spawn_agent`, `send_input`, `resume_agent`, `wait`, and
  `close_agent`
- a typed agent reference model instead of raw thread-id strings
- full event and item parity, including the remaining collaboration lifecycle
  surfaces
- config helpers for `features.multi_agent` and `[agents.*]`
- end-to-end tests against app-server behavior
- examples that distinguish true subagents from manual thread concurrency

Until that exists, this guide is the correct place to explain the feature in
full without overstating current SDK support.
