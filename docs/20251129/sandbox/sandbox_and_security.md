# Sandbox and security updates to mirror in the Elixir SDK

Upstream changes:
- Windows sandbox marks `<workspace_root>/.git` read-only in workspace-write mode and refines world-writable directory scanning/deduplication.
- Improved sandbox command bypass when a policy already approved the action; clarified sandbox strings and warnings (including Mac/NetBSD hardening fixes).
- PowerShell `apply_patch` parsing fixes for Windows and better handling of sandbox command assessment regressions.

Impact for the Elixir port:
- Expect new warning strings and scan results when running on Windows; tests that match exact text may need updates.
- Read-only git detection now emits messages like `Read-only git dir: C:/workspace/.git` and world-writable warnings deduplicate mixed separators (e.g., `World-writable directory: C:/Temp`).
- Approval flows may short-circuit for known-safe commands; align any SDK-side gating with the upstream behavior.
- If the SDK shells out on Windows, ensure path handling and read-only git detection match the CLI.

Action items:
- Refresh platform-specific fixture expectations for sandbox warnings.
- Document the read-only `.git` behavior in any Windows-facing guides for the SDK.
- Confirm apply_patch handling in Windows CI (if applicable) still passes with upstream parsing changes.
- Add runnable examples that show normalized warnings and policy-approved bypass (see `examples/sandbox_warnings_and_approval_bypass.exs`).
