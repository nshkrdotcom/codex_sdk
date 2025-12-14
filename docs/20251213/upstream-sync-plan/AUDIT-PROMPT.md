# Agent Prompt: Upstream Sync Documentation Audit

## Task Overview

You are tasked with critically auditing and improving documentation that analyzes upstream changes from two OpenAI projects and plans their porting to an Elixir SDK. Your job is to:

1. **Independently analyze** the same upstream repositories
2. **Compare** your findings against the existing documentation
3. **Identify** errors, omissions, or inaccuracies
4. **Edit** the documentation to correct any issues

---

## Context

### The Project

This is an Elixir SDK (`codex_sdk`) that ports functionality from two official OpenAI projects:

1. **openai-agents-python** - The OpenAI Agents Python SDK
   - Location: `/home/home/p/g/n/codex_sdk/openai-agents-python/`
   - Upstream: https://github.com/openai/openai-agents-python
   - Recent sync: commit `0d2d771` → `71fa12c` (v0.6.2 → v0.6.3)

2. **codex** (codex-rs) - The OpenAI Codex CLI written in Rust
   - Location: `/home/home/p/g/n/codex_sdk/codex/`
   - Upstream: https://github.com/openai/codex
   - Recent sync: commit `6eeaf46ac` → `a2c86e5d8`

3. **Elixir Port** - The SDK being updated
   - Location: `/home/home/p/g/n/codex_sdk/`
   - Main code: `/home/home/p/g/n/codex_sdk/lib/codex/`

### Documentation to Audit

Located at `/home/home/p/g/n/codex_sdk/docs/20251213/upstream-sync-plan/`:

| File | Purpose |
|------|---------|
| `00-overview.md` | Executive summary and document index |
| `01-agents-python-changes.md` | Analysis of Python SDK changes |
| `02-codex-rs-changes.md` | Analysis of Codex CLI changes |
| `03-elixir-port-gaps.md` | Gap analysis vs Elixir implementation |
| `04-porting-requirements.md` | Detailed porting requirements |
| `05-implementation-plan.md` | Phased implementation roadmap |

---

## Your Analysis Tasks

### Task 1: Analyze openai-agents-python Changes

Examine the Python SDK repository to verify and expand the documented changes:

```bash
cd /home/home/p/g/n/codex_sdk/openai-agents-python

# View commit range
git log --oneline 0d2d771..71fa12c

# For each significant commit, examine:
git show <commit> --stat
git diff <commit>~1 <commit> -- src/agents/

# Key files to examine:
# - src/agents/run.py (Runner, RunOptions, response chaining)
# - src/agents/_run_impl.py (execution implementation)
# - src/agents/usage.py (Usage normalization)
# - src/agents/agent.py (Agent class, as_tool, on_stream)
# - src/agents/items.py (Item types, ModelResponse)
# - src/agents/stream_events.py (streaming event types)
# - src/agents/models/chatcmpl_helpers.py (logprobs handling)
# - src/agents/models/chatcmpl_stream_handler.py (streaming)
# - src/agents/models/openai_chatcompletions.py (model interface)
# - src/agents/memory/session.py (session protocol)
# - src/agents/realtime/ (realtime API support)
```

**Questions to Answer**:
1. Are all significant API changes documented?
2. Are the commit attributions correct?
3. Are the code examples accurate?
4. Are there any changes that were missed?
5. Is the priority assessment correct?

### Task 2: Analyze codex-rs Changes

Examine the Codex CLI repository:

```bash
cd /home/home/p/g/n/codex_sdk/codex

# View commit range
git log --oneline 6eeaf46ac..a2c86e5d8 | head -100

# Key areas to examine:
# - codex-rs/core/src/config/ (configuration system)
# - codex-rs/core/src/config_loader/ (layer loading)
# - codex-rs/core/src/openai_models/ (models manager)
# - codex-rs/core/src/skills/ (skills system)
# - codex-rs/core/src/shell_snapshot.rs (shell capture)
# - codex-rs/otel/src/ (OpenTelemetry)
# - codex-rs/protocol/src/ (protocol types)
# - codex-rs/app-server/src/ (message handling)
# - codex-rs/tui2/ (new TUI)
```

**Questions to Answer**:
1. Are the major architectural changes captured?
2. Are protocol/event changes accurately documented?
3. Are there new features that were overlooked?
4. Is the relevance assessment for each change correct?
5. Are the Rust code references accurate?

### Task 3: Analyze Current Elixir Port

Examine the Elixir SDK to verify the gap analysis:

```bash
cd /home/home/p/g/n/codex_sdk

# List all modules
find lib/codex -name "*.ex" | sort

# Key modules to examine:
# - lib/codex.ex (main API)
# - lib/codex/thread.ex (thread management)
# - lib/codex/options.ex (global options)
# - lib/codex/thread/options.ex (thread options)
# - lib/codex/events.ex (event types)
# - lib/codex/items.ex (item types)
# - lib/codex/turn/result.ex (turn results)
# - lib/codex/session.ex (session management)
# - lib/codex/agent.ex (agent configuration)
# - lib/codex/tools.ex (tool system)
# - lib/codex/exec.ex (codex-rs subprocess)
```

**Questions to Answer**:
1. Is the current feature inventory accurate?
2. Are the identified gaps real?
3. Are there existing features that could satisfy some requirements?
4. Is the module impact analysis correct?
5. Are there additional modules that should be created?

---

## Audit Criteria

### Accuracy Checks

For each documented change, verify:
- [ ] Commit hash is correct
- [ ] File paths are accurate
- [ ] Code snippets match actual implementation
- [ ] Feature descriptions are precise
- [ ] Priority assessments are justified

### Completeness Checks

Ensure documentation covers:
- [ ] All significant commits in the range
- [ ] All new public API additions
- [ ] All breaking changes (if any)
- [ ] All new configuration options
- [ ] All new event/message types
- [ ] All dependency changes

### Consistency Checks

Verify internal consistency:
- [ ] Feature names match across documents
- [ ] Priority levels are consistent
- [ ] Implementation phases align with requirements
- [ ] Test requirements match implementation plan
- [ ] No contradictions between documents

### Quality Checks

Assess documentation quality:
- [ ] Code examples are syntactically correct
- [ ] Elixir code follows conventions
- [ ] Type specs are accurate
- [ ] Error handling is addressed
- [ ] Edge cases are considered

---

## Common Issues to Look For

### In Python SDK Analysis

1. **Missed decorator changes** - Check for new `@field_validator`, `@model_validator`
2. **Type annotation changes** - New TypedDicts, Protocol classes
3. **Default value changes** - Parameters with new defaults
4. **Deprecations** - Any deprecated functions or parameters
5. **New exceptions** - Custom exception classes added

### In codex-rs Analysis

1. **Protocol version changes** - v1 vs v2 differences
2. **Event type additions** - New EventMsg variants
3. **Config key changes** - Renamed or restructured config
4. **Feature flags** - New rollout flags or experimental features
5. **Platform-specific code** - Windows/macOS/Linux differences

### In Gap Analysis

1. **Over-estimation of gaps** - Features that already exist differently
2. **Under-estimation of complexity** - Features harder than described
3. **Dependency conflicts** - New deps that conflict with existing
4. **Backwards compatibility issues** - Changes that might break users
5. **Missing test coverage** - Areas needing more tests than stated

---

## Output Format

After your analysis, produce:

### 1. Audit Report

Create or update `AUDIT-REPORT.md` with:
- Summary of findings
- List of errors found
- List of omissions
- List of suggested improvements
- Severity assessment (Critical/Major/Minor)

### 2. Document Edits

For each document with issues:
- Make direct edits to correct errors
- Add missing information
- Remove inaccurate claims
- Improve code examples
- Add clarifying notes

### 3. Change Log

Document what you changed:
```markdown
## Audit Changes

### 01-agents-python-changes.md
- Fixed: Incorrect commit hash for logprobs feature
- Added: Missing `nest_handoff_history` parameter
- Removed: Inaccurate claim about X

### 02-codex-rs-changes.md
- Fixed: Wrong file path for skills module
- Added: Missing protocol v2 changes
- Updated: More accurate complexity estimates
```

---

## Execution Instructions

1. **Read all existing documentation first** to understand what was claimed

2. **Systematically verify each claim** by examining the actual code:
   ```bash
   # For each commit mentioned
   git show <commit> --stat
   git show <commit> -- <specific_file>
   ```

3. **Search for missed changes**:
   ```bash
   # Find all changed files
   git diff --stat 0d2d771..71fa12c

   # Search for specific patterns
   git log --all --oneline --grep="keyword"
   ```

4. **Cross-reference with tests** to understand intended behavior:
   ```bash
   # Python tests
   ls openai-agents-python/tests/

   # Rust tests
   find codex/codex-rs -name "*test*" -type f
   ```

5. **Check for documentation in upstream**:
   ```bash
   # Python docs
   ls openai-agents-python/docs/

   # Rust docs
   ls codex/codex-rs/*/README.md
   ```

6. **Make edits directly** - don't just report issues, fix them

---

## Quality Standards

Your edits should:
- Maintain consistent formatting
- Use accurate technical terminology
- Provide working code examples
- Include correct file paths
- Reference actual commit hashes
- Be actionable and specific

---

## Time Budget

Allocate your effort approximately:
- 30% - Analyzing openai-agents-python
- 30% - Analyzing codex-rs
- 20% - Analyzing Elixir port
- 20% - Writing audit report and making edits

---

## Final Deliverables

1. `AUDIT-REPORT.md` - Your findings and assessment
2. Updated versions of any documents with errors
3. Optional: `ADDITIONAL-FINDINGS.md` for significant discoveries not in original scope

Begin your analysis now. Be thorough, critical, and constructive.
