# New Protocol Types from Git Pull

## Overview

The pull introduced several new protocol types for the skills/list operation.

## New Operations

### Op::ListSkills

**File**: `codex-rs/protocol/src/protocol.rs`

```rust
/// Request skills discovery for one or more working directories
Op::ListSkills {
    /// Working directories to scope repo skills discovery.
    /// When empty, the session default working directory is used.
    cwds: Vec<PathBuf>,
}
```

**Purpose**: Allows clients to dynamically query available skills.

**Usage**:
```rust
// Get skills for session's default cwd
codex.submit(Op::ListSkills { cwds: vec![] }).await?;

// Get skills for specific directories
codex.submit(Op::ListSkills {
    cwds: vec![
        PathBuf::from("/project/a"),
        PathBuf::from("/project/b"),
    ]
}).await?;
```

## New Events

### EventMsg::ListSkillsResponse

**File**: `codex-rs/protocol/src/protocol.rs`

```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct ListSkillsResponseEvent {
    pub skills: Vec<SkillsListEntry>,
}

/// Skills and errors for a specific working directory
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SkillsListEntry {
    pub cwd: PathBuf,
    pub skills: Vec<SkillMetadata>,
    pub errors: Vec<SkillErrorInfo>,
}
```

**Purpose**: Server response containing discovered skills per working directory.

## New Types

### SkillScope Enum

**Files**:
- `codex-rs/protocol/src/protocol.rs`
- `codex-rs/app-server-protocol/src/protocol/common.rs`

```rust
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum SkillScope {
    /// Skills in ~/.codex/skills (user-wide)
    User,
    /// Skills in .codex/skills within a git repository
    Repo,
}
```

### Updated SkillMetadata

**File**: `codex-rs/core/src/skills/model.rs`

```rust
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct SkillMetadata {
    pub name: String,
    pub description: String,
    pub path: PathBuf,
    pub scope: SkillScope,  // NEW FIELD
}
```

### SkillsListEntry (Protocol)

```rust
pub struct SkillsListEntry {
    pub cwd: PathBuf,
    pub skills: Vec<SkillMetadata>,
    pub errors: Vec<SkillErrorInfo>,
}
```

## App-Server Protocol Types

### SkillsListParams

**File**: `codex-rs/app-server-protocol/src/protocol/v2.rs`

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillsListParams {
    /// Working directories (empty = session default)
    pub cwds: Vec<PathBuf>,
}
```

### SkillsListResponse

```rust
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SkillsListResponse {
    pub data: Vec<SkillsListEntry>,
}
```

## Removed Fields

### SessionConfiguredEvent

**Before**:
```rust
pub struct SessionConfiguredEvent {
    // ...
    pub skill_load_outcome: Option<SkillLoadOutcomeInfo>,
}
```

**After**: Field removed. Clients must use `Op::ListSkills` to get skills.

## Migration Guide

### For Protocol Consumers

**Old Pattern** (push-based):
```rust
// Wait for session configured event with skills
let session_event = wait_for_session_configured().await;
let skills = session_event.skill_load_outcome;
```

**New Pattern** (request/response):
```rust
// Request skills explicitly
codex.submit(Op::ListSkills { cwds: vec![] }).await?;

// Handle response event
match event {
    EventMsg::ListSkillsResponse(response) => {
        for entry in response.skills {
            println!("CWD: {:?}", entry.cwd);
            for skill in entry.skills {
                println!("  - {} ({})", skill.name, skill.scope);
            }
        }
    }
    _ => {}
}
```

## JSON Wire Format

These examples reflect the **app-server JSON-RPC** method (`skills/list`), not the in-process core `Op` enum.

### Request (skills/list)

```json
{
    "id": 1,
    "method": "skills/list",
    "params": {
        "cwds": ["/path/to/project"]
    }
}
```

### Response

```json
{
    "id": 1,
    "result": {
        "data": [
            {
                "cwd": "/path/to/project",
                "skills": [
                    {
                        "name": "my-skill",
                        "description": "Does something useful",
                        "path": "/home/user/.codex/skills/my-skill/SKILL.md",
                        "scope": "user"
                    }
                ],
                "errors": []
            }
        ]
    }
}
```

## Elixir Porting Notes

To support these types in Elixir:

```elixir
# lib/codex/skills/scope.ex
defmodule Codex.Skills.Scope do
  @type t :: :user | :repo
end

# lib/codex/skills/metadata.ex
defmodule Codex.Skills.Metadata do
  use TypedStruct
  typedstruct do
    field :name, String.t(), enforce: true
    field :description, String.t(), enforce: true
    field :path, String.t(), enforce: true
    field :scope, Codex.Skills.Scope.t(), enforce: true
  end
end

# lib/codex/skills/list_entry.ex
defmodule Codex.Skills.ListEntry do
  use TypedStruct
  typedstruct do
    field :cwd, String.t(), enforce: true
    field :skills, [Codex.Skills.Metadata.t()], default: []
    field :errors, [Codex.Skills.Error.t()], default: []
  end
end

# lib/codex/events/list_skills_response.ex
defmodule Codex.Events.ListSkillsResponse do
  use TypedStruct
  typedstruct do
    field :skills, [Codex.Skills.ListEntry.t()], default: []
  end
end
```
