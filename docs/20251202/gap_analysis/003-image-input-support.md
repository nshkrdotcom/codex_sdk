# ADR 003: Add image input support to thread turns

- Status: Proposed
- Date: 2025-12-02

## Context
- Upstream SDKs accept mixed text/image inputs and forward local images via `--image` (codex/sdk/typescript/src/thread.ts:27-153, codex/sdk/typescript/src/exec.ts:99-103).
- The Elixir API only accepts plain string prompts (`@spec run(t(), String.t(), ...)` in lib/codex/thread.ex:66-69) and the exec arg builder has no image flag handling (lib/codex/exec.ex:187-255).

## Problem
- Elixir users cannot send local images with their prompts, so image-grounded flows available in Python/TypeScript are unavailable here. This also blocks parity testing for multimodal turns.

## Decision
- Extend the public thread API to accept a structured input list (text + local image entries) and normalize it into prompt + image paths.
- Update `Codex.Exec.build_args/1` to emit `--image` arguments for each path while retaining existing attachment handling.

## Actions
- Add unit tests covering mixed inputs and ensure streamed/buffered paths both forward images.
- Document the new input shape and add an example mirroring the upstream SDK.
