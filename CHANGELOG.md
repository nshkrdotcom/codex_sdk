# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2025-10-20

### Added
- Core Codex thread lifecycle with streaming, resumption, and structured output decoding (`Codex.Thread`, `Codex.Turn.Result`, `Codex.Events`, `Codex.Items`)
- GenServer-backed `Codex.Exec` process supervision, error handling, and tool invocation pipeline
- Approval policies, hook behaviour, registry support, and telemetry events for tooling approvals
- File staging registry, attachment helpers, parity fixtures, and harvesting script for Python SDK alignment
- Comprehensive telemetry module with OTLP exporter gating, metrics, and approval instrumentation
- Mix tasks (`mix codex.verify`, `mix codex.parity`), integration tests, and Supertester-powered contract suite
- Rich examples and documentation covering approvals, streaming, concurrency, observability, and design dossiers

### Changed
- Refreshed `README.md` with 0.2.0 usage guide, testing workflow, and observability configuration
- Expanded HexDocs configuration to include new guides, design notes, and release documentation
- Updated package metadata to ship changelog, examples, and assets with the Hex release

## [0.1.0] - 2025-10-11

Initial design release.
