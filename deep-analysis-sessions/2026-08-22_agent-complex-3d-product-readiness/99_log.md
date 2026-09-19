# Investigation Log

## 2026-08-22

- Read goal, philosophy, conformance, implementation-status, architecture, implementation-plan, workflow-contract, and issue documents.
- Mapped the package graph and current source targets.
- Traced Agent JSON-RPC dispatch through capability invocation, AutomationRunner, EditorSession/CommandStack, Swift-CAD evaluation, and universal geometry publication.
- Inspected representative sweep, revolve, loft, boolean, transaction, rollback, and capability-contract tests.
- Counted 126 automation-command and 38 typed Agent-request entries in the 164-entry static Agent catalog.
- Ran swift-CAD ledger check: 25 supported, 42 partial, 67 total.
- Ran swift-CAD public contract inventory: 75 routes.
- Ran swift-CAD goal contract: not achieved, 0/8 gates.
- Attempted focused `xcodebuild test` with a 20-minute timeout and Swift 6.4 snapshot toolchain. Build failed in `CADGeometrySourceProvider.swift`; test execution was cancelled and zero tests ran.
- Confirmed Rupa/RupaKit HEAD equals `origin/main`; confirmed RupaKit resolves swift-CAD by local path and that the swift-CAD worktree has 366 changed or untracked entries.
- Found no versioned machine-readable conformance manifest and confirmed the known backlog says the MCP bridge is not implemented.
