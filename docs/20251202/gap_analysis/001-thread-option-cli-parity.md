# ADR 001: Thread option parity with codex CLI

- Status: Proposed
- Date: 2025-12-02

## Context
- The TypeScript SDK forwards per-thread execution controls to the `codex exec` CLI, including sandbox mode, working directory, additional directories, Git repo checks, network/web-search toggles, approval policy, and per-thread model/reasoning overrides (codex/sdk/typescript/src/exec.ts:16-97, codex/sdk/typescript/src/threadOptions.ts:7-17).
- The Elixir thread options struct only carries metadata, labels, auto-run, and approval hook hints (lib/codex/thread/options.ex:6-66).
- The Elixir exec argument builder never emits the corresponding CLI flags/config entries beyond model + schema/attachments (lib/codex/exec.ex:187-255).

## Problem
- Callers of the Elixir SDK cannot opt into CLI capabilities that Python/TypeScript expose (sandbox selection, working directory overrides, network/web search enablement, Git check suppression, additional directories, approval policy, per-thread model + reasoning effort). This diverges from upstream behavior and prevents parity validation against Python fixtures.

## Decision
- Add the missing fields to `Codex.Thread.Options` with validation mirroring the CLI enum values.
- Extend `Codex.Exec.build_args/1` to emit `--sandbox`, `--cd`, `--add-dir`, `--skip-git-repo-check`, `--config sandbox_workspace_write.network_access`, `--config features.web_search_request`, `--config approval_policy`, and per-thread `--model`/`--config model_reasoning_effort` overrides.
- Thread/build helpers should merge per-thread defaults with global `Codex.Options` to preserve existing behavior while allowing overrides.

## Actions
- Update unit/integration tests to cover the new flags and ensure contract coverage against harvested Python fixtures once regenerated.
- Document the new thread option fields in the public API reference and examples.
