# Subagents

Subagents let Codex break a task into child agent threads and then bring the
results back to the parent. They are useful when the work can be split into
clean, bounded pieces such as codebase exploration, focused review passes, log
analysis, or a simple one-parent -> one-child investigation.

In this SDK, a good subagent workflow has two parts:

- the SDK control surface for structured operations such as configuration,
  discovery, inspection, streaming, and waiting on known child threads
- prompt instructions that tell Codex whether to delegate, how many children to
  spawn, which agent to use, whether to wait, and what summary to return

For broader background, setup details, and product-level guidance, see the
official Codex docs:

- [Subagents](https://developers.openai.com/codex/subagents)
- [Subagent concepts](https://developers.openai.com/codex/concepts/subagents)

## When Subagents Help

Subagents are a good fit when the work can be divided into independent pieces.

Typical examples:

- read-heavy codebase exploration
- multiple review passes with different goals
- tracing separate code paths in parallel
- log analysis or incident triage
- one child doing bounded research while the parent keeps the main thread clean

Be more careful with write-heavy workflows. Multiple agents editing the same
area at once can create conflicts and extra coordination work.

## Availability and Behavior

Current Codex releases enable subagent workflows by default. Codex only uses
subagents when you explicitly ask for them, and each child agent adds token
cost because it does its own model and tool work.

Subagents inherit the parent session's sandbox and approval posture unless a
custom agent overrides those settings. That makes the child behave like a real
continuation of the parent workflow rather than an unrelated fresh session.

## The Two Parts of Using Subagents From Elixir

The clean mental model is:

- use the SDK control surface for deterministic, structured operations
- use prompts for delegation behavior

The direct SDK surface for this guide is:

- `Codex.Subagents.list/2`
- `Codex.Subagents.children/3`
- `Codex.Subagents.read/3`
- `Codex.Subagents.source/1`
- `Codex.Subagents.parent_thread_id/1`
- `Codex.Subagents.child_thread?/1`
- `Codex.Subagents.await/3`
- `Codex.Protocol.SessionSource`
- `Codex.Protocol.SubAgentSource`

| Concern | Use the SDK control surface | Use prompt instructions |
| --- | --- | --- |
| Enable or tune subagent settings | Yes | No |
| Set `agents.max_threads` and `agents.max_depth` | Yes | No |
| Discover child threads for a parent | Yes | No |
| Inspect child metadata such as parent id, depth, role, or nickname | Yes | No |
| Observe collaboration events and tool-call items | Yes | No |
| Read or continue a known child thread | Yes | No |
| Decide whether to delegate | No | Yes |
| Decide how many children to spawn | No | Yes |
| Choose `explorer`, `worker`, or a custom agent | No | Yes |
| Tell the parent to wait, summarize, or keep working | No | Yes |

This split matters. The SDK should own the structured parts. Your prompt should
own the delegation strategy.

Just as important, the SDK does not expose prompt-template helper APIs for this
workflow. Prompt snippets in this guide are documented practice, not helper
functions. There is no host-side `spawn_agent/3`, `delegate/2`, or
`wait_and_summarize/2` surface because those choices are still model-mediated.

## Configure Subagents

Global subagent settings live under `[agents]` in `.codex/config.toml`.

```toml
[agents]
max_threads = 2
max_depth = 1
```

Useful defaults from the Codex docs:

- `agents.max_threads` defaults to `6`
- `agents.max_depth` defaults to `1`

For a simple one-parent -> one-child workflow, `max_depth = 1` is usually what
you want. It allows the parent to spawn a child but prevents the child from
building a deeper tree.

You can also set these values through the SDK when you are connected to Codex:

```elixir
{:ok, conn} = Codex.AppServer.connect(codex_opts, experimental_api: true)
{:ok, _} = Codex.AppServer.config_write(conn, "features.multi_agent", true)
{:ok, _} = Codex.AppServer.config_write(conn, "agents.max_threads", 2)
{:ok, _} = Codex.AppServer.config_write(conn, "agents.max_depth", 1)
```

## Built-In and Custom Agents

Codex ships with three useful built-in agents:

- `default` for general-purpose fallback work
- `worker` for implementation and fixes
- `explorer` for read-heavy exploration

When you need a narrower role, define a custom agent in one standalone TOML
file under `.codex/agents/` for project-scoped agents or `~/.codex/agents/`
for personal agents.

Every custom agent file should define:

- `name`
- `description`
- `developer_instructions`

Optional fields such as `nickname_candidates`, `model`,
`model_reasoning_effort`, and `sandbox_mode` inherit from the parent when you
omit them.

Example:

```toml
name = "reviewer"
description = "PR reviewer focused on correctness, security, and missing tests."
developer_instructions = """
Review code like an owner.
Prioritize correctness, security, behavior regressions, and missing test coverage.
"""
nickname_candidates = ["Atlas", "Delta", "Echo"]
model = "gpt-5.4"
model_reasoning_effort = "medium"
sandbox_mode = "read-only"
```

Keep custom agents narrow and opinionated. A good custom agent has one clear
job and instructions that keep it from drifting into adjacent work.

## Basic SDK Workflow

The normal Elixir flow is:

1. Configure subagent limits.
2. Start a parent thread.
3. Prompt the parent to spawn exactly the children you want.
4. Observe the workflow in streamed events.
5. Discover the child thread or threads from the SDK control surface.
6. Inspect the child metadata.
7. Read, follow up on, or await the child thread as needed.

Here is the shape of a simple one-parent -> one-child flow:

```elixir
{:ok, conn} = Codex.AppServer.connect(codex_opts, experimental_api: true)
{:ok, _} = Codex.AppServer.config_write(conn, "features.multi_agent", true)
{:ok, _} = Codex.AppServer.config_write(conn, "agents.max_threads", 2)
{:ok, _} = Codex.AppServer.config_write(conn, "agents.max_depth", 1)

{:ok, parent} =
  Codex.start_thread(codex_opts, %{
    transport: {:app_server, conn},
    working_directory: File.cwd!(),
    model: "gpt-5.4"
  })

prompt = """
Spawn exactly one child agent for this task.
Use the explorer agent.
Do not spawn any additional agents.
The child must not spawn more agents.
Inspect lib/codex/subagents.ex and summarize what host-side controls it exposes.
Wait for the child before answering.
If subagents are unavailable, continue solo and say so explicitly.
"""

{:ok, parent_result} = Codex.Thread.run(parent, prompt, %{timeout_ms: 120_000})

{:ok, [child]} = Codex.Subagents.children(conn, parent_result.thread.thread_id)
source = Codex.Subagents.source(child)

IO.inspect(%{
  child_thread_id: child["id"],
  parent_thread_id: Codex.Subagents.parent_thread_id(source),
  source_kind: Codex.Protocol.SessionSource.source_kind(source),
  depth: source.sub_agent.depth,
  agent_role: source.sub_agent.agent_role,
  agent_nickname: source.sub_agent.agent_nickname
})

{:ok, _child_snapshot} = Codex.Subagents.read(conn, child["id"], include_turns: true)

{:ok, child_thread} =
  Codex.resume_thread(child["id"], codex_opts, %{
    transport: {:app_server, conn},
    working_directory: File.cwd!()
  })

{:ok, _child_result} =
  Codex.Thread.run(child_thread, "Reply with one sentence that starts with 'child follow-up:'")

{:ok, :completed} = Codex.Subagents.await(conn, child["id"], timeout: 30_000)
```

The important pattern is simple:

- the prompt tells Codex how to delegate
- the SDK gives you structured visibility and control over the resulting child
  thread

For a runnable end-to-end version of this flow, see
`examples/live_subagent_host_controls.exs`.

## Streaming and Observability

Subagent workflows are much easier to debug when you stream events instead of
waiting for only the final answer.

The SDK should let you observe collaboration activity such as:

- child spawn begin and end
- follow-up interaction begin and end
- waiting begin and end
- close begin and end
- typed collaboration tool-call items in the item stream

That gives you a reliable way to answer questions such as:

- did the parent actually spawn a child?
- how many child threads were created?
- which child thread ids were used?
- did the parent wait for the child or continue immediately?

## Prompting Strategy

Codex does not spawn subagents automatically. If you want subagents, say so
clearly.

Good subagent prompts usually specify:

- whether to delegate at all
- the exact number of children to create
- which built-in or custom agent to use
- whether children may spawn additional children
- whether the parent should wait or keep working
- what final answer shape to return

These prompt patterns are documentation only. They are not wrapped in helper
APIs because delegation remains a model decision inside the turn.

### A Reliable One-Child Prompt

```text
Spawn exactly one child agent for this task.
Use the explorer agent.
Do not spawn any additional agents.
Inspect lib/my_app/payments.ex and explain the payment lifecycle.
Wait for the child to finish before answering.
Return a concise summary with file references.
If subagents are unavailable, continue solo and say so explicitly.
```

This is a good default pattern because it keeps the workflow bounded and easy to
inspect from Elixir.

### A Good Parallel Review Prompt

```text
Review this branch with parallel subagents.
Spawn one child for security risks, one for test gaps, and one for maintainability.
Wait for all children, then summarize the findings by category with file references.
Do not create any additional agents beyond those three.
```

### Prompting Tips

- ask for an exact number of children, not "some" or "a few"
- name the agent you want when you care about behavior
- say whether the parent should wait
- say what the final answer should look like
- add an explicit fallback so the run still succeeds without subagents

## Working With Child Threads

Once a child exists, treat it as a first-class thread.

The SDK control surface should let you:

- list the children for a parent
- inspect the child's source metadata
- confirm the parent/child relationship
- read the child thread
- stream or run direct follow-up work on the child
- wait for the child to reach a final state

That is the part Elixir should own. It is structured, deterministic, and
useful for application code.

In practice, `Codex.Subagents.source/1` returns a `%Codex.Protocol.SessionSource{}`
and subagent threads use `%Codex.Protocol.SubAgentSource{}` for variant-specific
metadata. `thread_spawn` children expose the structured fields host code usually
needs most:

- `parent_thread_id`
- `depth`
- `agent_nickname`
- `agent_role`

## Approvals and Sandbox Controls

Subagents inherit the parent session's sandbox and approval posture unless you
override them in a custom agent.

That means:

- a read-only parent usually leads to read-only children unless you opt out
- a stricter custom agent can be safer for review or exploration tasks
- approval failures in a child flow back into the broader workflow instead of
  silently disappearing

For review, exploration, and documentation tasks, a read-only child is often
the right default.

## Choosing Agents and Models

Start simple.

- use `gpt-5.4` for the parent and for agents handling harder reasoning or
  ambiguous work
- use `gpt-5.3-codex-spark` for faster read-heavy or summarization-focused
  agents
- use `medium` reasoning effort as the default unless you have a clear reason
  to go lower or higher

If you create custom agents, pin model or reasoning settings only when the role
truly benefits from it. Otherwise, let the child inherit the parent session's
defaults.

## Recommended Starting Point

If you are new to subagents, start with this exact pattern:

1. Set `agents.max_threads = 2`.
2. Set `agents.max_depth = 1`.
3. Start one parent thread on `gpt-5.4`.
4. Ask the parent to spawn exactly one `explorer` child.
5. Tell the parent to wait for the child.
6. Use the SDK control surface to confirm the child exists, inspect its source,
   and await completion.

That keeps the workflow small, easy to reason about, and easy to test.

## Further Reading

- [Subagents](https://developers.openai.com/codex/subagents)
- [Subagent concepts](https://developers.openai.com/codex/concepts/subagents)
