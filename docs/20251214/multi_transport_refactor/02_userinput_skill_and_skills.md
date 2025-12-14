# `UserInput::Skill` + Skills: What Exists, What’s Exposed, What’s Blocked

## 1) Where `UserInput::Skill` exists (core protocol)

The **core** protocol enum includes a skill variant:

- `codex/codex-rs/protocol/src/user_input.rs:25` defines `UserInput::Skill { name, path }`

This is “real” and wired into core processing. Skill bodies are injected later (see `codex/codex-rs/protocol/src/models.rs:333`).

## 2) Where `UserInput::Skill` is used today (TUI)

The interactive TUI constructs `UserInput::Skill` inputs and submits them with the rest of the user message:

- `codex/codex-rs/tui/src/chatwidget.rs:1754` pushes `UserInput::Skill { name, path }`
- `codex/codex-rs/tui/src/chatwidget.rs:1761` sends `Op::UserInput { items }`

Core then turns those `UserInput::Skill` inputs into injected instructions:

- `codex/codex-rs/core/src/skills/injection.rs:69` pattern matches `UserInput::Skill { name, path }`

## 3) Why app-server clients cannot send `UserInput::Skill` today (“exposed”)

When we say **“app-server does not expose `UserInput::Skill`”**, we mean:

- The app-server **wire protocol** (`turn/start` input union) does **not** include any JSON representation for the skill variant.
- Therefore, an app-server client cannot send a well-formed `turn/start` request that carries a skill input.

Evidence:

- `codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1289` defines app-server `UserInput` as only:
  - `Text`
  - `Image`
  - `LocalImage`
- There is no `Skill` variant in that enum, and the conversion from core explicitly treats extra variants as unreachable (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1311`).

Bottom line:

- **TUI can use `UserInput::Skill`** (in-process).
- **App-server clients cannot** (protocol has no such variant).
- **Exec JSONL clients cannot** (exec accepts prompt + images only).
- Therefore, **TS SDK cannot**, and **`codex_sdk` cannot** until upstream app-server adds it (or `codex_sdk` emulates it).

## 4) Were “Skills” already in the Rust codebase before the 2025-12-14 pull?

Yes.

Even at the pre-pull commit (`a2c86e5d8`), the Rust tree already contained skills implementation files under:

- `codex-rs/core/src/skills/*` (loader, injection, rendering, models)

The 2025-12-14 pull (commit `5d77d4db6`) refactors skills loading and adds a manager + list operation:

- New: `codex/codex-rs/core/src/skills/manager.rs:11` (`SkillsManager`)
- New protocol op/event: `codex/codex-rs/protocol/src/protocol.rs:189` (`Op::ListSkills`) and `codex/codex-rs/protocol/src/protocol.rs:1667` (`ListSkillsResponseEvent`)
- New app-server method: `codex/codex-rs/app-server-protocol/src/protocol/common.rs:124` (`skills/list`)

## 5) What `codex_sdk` can port “now” vs what requires upstream changes

### Implementable once `codex_sdk` supports app-server

Once `codex_sdk` can speak app-server JSON-RPC, it can expose skills discovery via:

- `skills/list` (`codex/codex-rs/app-server-protocol/src/protocol/common.rs:124`)
- Types: `SkillsListParams`, `SkillsListEntry`, `SkillMetadata`, `SkillScope` (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:976`)

This gets you:
- listing skills per cwd
- returning errors per cwd

### Still blocked even with app-server (today)

Selecting a skill as a first-class input is blocked until upstream exposes it over app-server:

- missing in app-server `UserInput` union (`codex/codex-rs/app-server-protocol/src/protocol/v2.rs:1289`)

### Options to close the gap

1. **Upstream change (preferred for true parity)**:
   - Add `Skill { name, path }` to app-server `UserInput` in `codex-rs/app-server-protocol`
   - Add conversion mappings in `into_core` / `From<CoreUserInput>`
   - Update app-server docs/examples accordingly

2. **SDK emulation (acceptable if “parity” means “equivalent behavior”)**:
   - `codex_sdk` reads the selected `SKILL.md` and injects its contents into the prompt (as `text`) or into system/developer instructions.
   - This will **not** exactly match upstream core injection semantics, but it can approximate the effect for clients.

