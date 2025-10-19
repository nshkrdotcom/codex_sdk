# Prompt: Achieve Integration & Release Readiness

## Required Reading
1. `docs/20251018/codex-sdk-completion/integration-readiness.md`
2. `docs/08-tdd-implementation-guide.md` (dependency management & CI sections)
3. `mix.exs` (application configuration, package metadata)
4. `README.md`, `docs/02-architecture.md`, `docs/05-api-reference.md` for current public docs
5. Existing scripts (`scripts/harvest_python_fixtures.py`) for examples of tooling structure.

## Implementation Instructions
1. Implement the remaining dependency tasks:
   - Add `vendor/codex` submodule (sparse checkout) and supporting Mix tasks.
   - Provide binary verification and installation tooling (`mix codex.install`, `mix codex.verify`).
2. Harden configuration handling:
   - Ensure runtime validation for API key, base URL, codex path with clear error messages.
   - Update documentation to explain configuration and authentication flows.
3. Prepare release packaging:
   - Adjust package file lists, craft release checklist, and document binary distribution strategy.
4. Update README/HexDocs with comprehensive usage guides, examples, and telemetry references.
5. Run the full test suite, `mix compile --warnings-as-errors`, `mix format`, and any new Mix tasks introduced.
6. Produce release notes and checklist updates confirming completion with zero warnings.
