# ADR 004: Implement file upload + temporary attachment helpers

- Status: Proposed
- Date: 2025-12-02

## Context
- The attachments design calls for parity with Python, including `Codex.Files.upload/2` and `Codex.Files.temporary/1` RAII helpers (docs/design/attachments-files.md:3-32).
- The current Elixir implementation only stages local files and attaches them to thread options (lib/codex/files.ex:1-152); no upload or temporary helper exists.

## Problem
- SDK callers cannot push staged files to Codex via the documented upload API, nor can they create scoped temporary attachments that auto-clean. This leaves Python workflows (upload + disposable attachments) unported.

## Decision
- Add an upload pipeline that streams staged files to the CLI/API and returns attachment descriptors compatible with the existing registry.
- Provide a `temporary/1` helper that stages ephemeral files with automatic cleanup semantics.

## Actions
- Build unit/integration tests around upload success/failure and temporary lifecycle.
- Update public docs to describe the new helpers and regeneration steps for Python parity fixtures that cover uploads.
