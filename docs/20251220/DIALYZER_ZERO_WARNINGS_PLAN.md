# Dialyzer Zero-Warnings Plan

## Goal
Remove all dialyzer suppressions, fix the root causes, and keep behavior aligned with upstream `codex` while ensuring `mix dialyzer` and `mix test` complete with zero warnings.

## Constraints
- Do not edit vendored `codex/`; use it only to confirm intent if behavior changes are required.
- Prefer correcting specs and guards over altering runtime behavior.
- If a behavior change is necessary, confirm the expected behavior by inspecting `codex/` and document the reasoning.

## Scope
- In scope: `mix.exs`, `.dialyzer_ignore.exs`, and affected modules in `lib/` and `lib/mix/tasks/`.
- Out of scope: changes to `codex/` or broad refactors unrelated to dialyzer issues.

## Files to examine
- `mix.exs`
- `.dialyzer_ignore.exs`
- `lib/codex/exec.ex`
- `lib/codex/options.ex`
- `lib/codex/thread.ex`
- `lib/codex/tools.ex`
- `lib/codex/config/constrained.ex`
- `lib/mix/tasks/codex.parity.ex`
- `lib/mix/tasks/codex.verify.ex`

## Workflow
1. Disable ignores and capture real warnings
   - Temporarily remove or bypass `.dialyzer_ignore.exs` to surface all warnings.
   - Run `mix dialyzer --format short` and collect the precise warnings.

2. Classify each warning
   - Spec mismatch: spec is broader/narrower than actual return types.
   - Unreachable pattern or guard: pattern never matches per inferred types.
   - Incorrect type in external dependency: refine wrapper or add guard to maintain safety.

3. Upstream intent check for behavior changes
   - If a warning implies a behavior change (not just a spec correction), inspect `codex/` to determine the intended behavior.
   - Record the source file and rationale in code comments only when non-obvious.

4. Fix warnings at the source
   - Adjust specs to match behavior (or adjust behavior to match upstream intent).
   - Tighten pattern matches or add guards to match actual types.

5. Remove suppressions
   - Delete `.dialyzer_ignore.exs`.
   - Remove `ignore_warnings` from `mix.exs`.

6. Validate
   - Run `mix dialyzer --format short` (expect zero warnings).
   - Run `mix test` (expect green).

7. Documentation updates (if needed)
   - If behavior changes are made, update `README.md`, relevant docs, and `CHANGELOG.md`.

## Validation commands
- `mix dialyzer --format short`
- `mix test`

## Risks
- Some warnings may be rooted in upstream types (e.g., `:erlexec`); resolve via safe wrapper types or guards.
- Behavior changes may affect public API expectations; update tests/docs if changed.
