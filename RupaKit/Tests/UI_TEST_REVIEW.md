# UI test review

## Findings

| ID | Evidence | Problem | Resolution |
|---|---|---|---|
| UI-T1 | `Rupa/Rupa/RupaUITests/AppOperationCoverageUITests.swift`, `launchApp` | Every test launches and zooms the App, then drives global pointer/keyboard input. | Routine Test selects only non-window package contracts. |
| UI-T2 | `AppFailureSweepUITests.clearTheScreen` | Repeated activation and optional hiding of unrelated applications commandeer the desktop; cleanup cannot be guaranteed after process termination. | Remove takeover and hiding. Obstructed dedicated-session diagnostics fail without changing other apps. |
| UI-T3 | `AppUITests.testCanvasSurfaceToolOpensSheetLoftAndRejectsMissingProfiles` | Expects an error after clicking Preview, but production disables Preview and exposes `Modeling.refusal` before execution. | Align the retained diagnostic and verify the production refusal getter without a window. |
| UI-T4 | `testSelectingObjectShowsViewportAffordance`, Model menu coverage | Presence of a handle or menu item is not proof of the resulting coordinate or geometry. Only Box is committed by the ten-item menu test. | Retain axis/placement, CAD geometry, Mesh preview/commit and atomic Inspector transaction tests in the contract scheme. Do not label these as GUI coverage. |
| UI-T5 | `WorkspaceCanvasToolbarNativeTests`, `ViewportNativeObjectAffordancePressTests` | Package tests also call `orderFront`; executing a whole package is not inherently non-interfering. | Use an explicit test allowlist, excluding mounted-window tests. |
| UI-T6 | The contract runner's result bundles, compared with `Test-RupaUIPackageTests-2026.09.17_11-58-24-+0900.xcresult` | xcodebuild can return exit 0 with zero executed tests. Existing isolated tests do pass when their xcresult is inspected, so this is not a general runtime failure. | The new runner rejects zero tests, failures and skips; quiet console output is not evidence of either success or absence of tests. |

## Coverage and limits

`scripts/test-ui-contracts.sh` reuses production binding-to-Workspace, draft-to-kernel,
Mesh preview/commit, stale-preview and affine-transform tests. Rendering's
`ViewportBodyTransformInputTests` checks named axes, pivots, occurrence identity,
atomic placement, Undo and preview geometry without mounting a window.

These checks do not prove that a visible button is reachable, that rendered
pixels match geometry, or that pointer hit testing reaches the correct native
handle. Those remain direct inspection tasks; passing contract tests must not
be reported as complete GUI acceptance. Historical App test results must retain
their original snapshot and scope.

## Execution

Verified on macOS 27.0: 29 UI contract tests and 6 rendering contract tests
passed with no failures or skips. Results are in
`/var/folders/c4/bcbjzcj556d3xj45z64rzjmw0000gn/T/rupa-ui-contracts.8AgfFU/`.
Parameterized case counts are distinct from these 35 test-function results.

From `RupaKit`, run `bash scripts/test-ui-contracts.sh`. The run is bounded
to 120 seconds per target. No App launch, UI runner, window ordering or system event
injection is part of this entry point. `scripts/ui-contract-tests.txt` owns the
reviewed test selection, passed through the existing package schemes using
explicit command-line test IDs. The shared App scheme skips its foreground UI target;
this skip is not a passing test result. Run still launches the App intentionally.
