# Risk Mitigation Tracker

This document aggregates outstanding risks for the remaining implementation along with mitigation strategies and monitoring actions.

## Summary Table

| Risk | Impact | Likelihood | Mitigation | Owner | Status |
|------|--------|------------|------------|-------|--------|
| Rust submodule divergence | High | Medium | Pin commit, weekly sync review, `mix codex.verify` | SDK Lead | Open |
| Fixture drift vs Python | High | Medium | Automate harvesting, checksum manifest, nightly diff | QA | Open |
| Cross-platform binary behavior | Medium | Medium | CI macOS job, Docker image parity, manual smoke test | DevOps | Open |
| Tooling API mismatch | High | Medium | Contract tests for auto-run/tool call parity, design review with Python team | Feature Squad | Open |
| Attachment storage bloat | Medium | Medium | TTL cleanup job, telemetry alert on staged byte count | Platform | Open |
| Telemetry overload | Low | Medium | Sampling config, doc guidance, load tests pre-release | Observability | Planned |
| Approval deadlocks | High | Low | Default timeouts & fallback policies, Supertester stress tests | Security | Open |
| Coverage regression | Medium | Medium | Coverage gate in CI, parity harness coverage report | QA | Planned |
| Documentation lag | Medium | Medium | Update docs per milestone, doc review checklist | Docs | Open |

## Detailed Entries

### Rust Submodule Divergence
- **Context**: Vendored `codex-rs` must track upstream without accumulating local hacks.
- **Mitigation Actions**
  - Establish weekly cron to fetch upstream and open PR if divergence detected.
  - Store patches under `patches/codex-rs/` and re-apply automatically.
  - Require changelog entry and integration tests before bumping commit.
- **Monitoring**
  - `mix codex.verify` includes `git status vendor/codex` check.

### Fixture Drift vs Python
- **Context**: Golden JSONL fixtures can fall out of date as Python evolves.
- **Mitigation**
  - Maintain manifest with SHA256 per fixture.
  - Nightly CI job regenerates fixtures and fails if checksum changes.
  - Use GitHub issues template for documenting accepted fixture diffs.

### Tooling API Mismatch
- **Context**: Tool registry/auto-run semantics must mirror Python.
- **Mitigation**
  - Schedule design review with Python maintainers before implementation.
  - Build contract tests for tool invocation transcripts.
  - Maintain parity checklist for tooling features (decorators, metadata, approvals).

### Approval Deadlocks
- **Context**: Misconfigured approval policies could hang turn execution.
- **Mitigation**
  - Enforce default timeout with abort + error surface.
  - Provide async queue implementation with supervision.
  - Stress test using Supertester chaos helpers (simulate slow/failed approvals).

### Coverage Regression
- **Context**: As features land, coverage/lint gates must remain enforced.
- **Mitigation**
  - Set baseline threshold in `mix coveralls`.
  - Document process for adjusting baseline only with QA approval.
  - Integrate coverage trend reporting into CI dashboards.
