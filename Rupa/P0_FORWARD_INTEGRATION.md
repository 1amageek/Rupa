# P0 Forward Contract Integration

## Decision

Rupa revision `0c5868990c9c4bae2968fba324431a9a5fee5f1b` adopts the forward
Swift-CAD contract preserved at revision
`26406fcdaa09cf5eed6d291f7e29afe72916cfc8`. The reproducible repository
tuple and dependency declarations are recorded in `P0_FORWARD_INTEGRATION.json`.

The recoverable legacy integration baseline remains unchanged. This forward
checkpoint is a downstream contract integration milestone, not a claim that all
P0 completion gates are achieved.

## Integrated contracts

| Contract | Rupa integration |
|---|---|
| Generated topology identity | Stable subshape references replace persistent-name parsing in selection and mutation paths. |
| Modeling tolerance | Evaluation, validation, analysis, rendering, and tests pass explicit tolerance values. |
| Authored surface trim | `SurfaceTrimFeature` owns authored loops; source B-spline surfaces retain their independent parameter domain. |
| Sketch tangency | Line/circular and spline tangency payloads preserve side, contact, endpoint, and orientation. |
| Failure behavior | Unsupported generated-topology offset gap-fill values fail before document mutation. |

## Executed evidence

The following checks were executed against the recorded tuple on 2026-07-22:

| Check | Result |
|---|---|
| Full RupaKit package build | Passed |
| Surface trim add, replace, and remove behavior | Passed in the focused contract run. |
| Stable edge offset and explicit gap-fill rejection | Passed in the focused contract run. |
| Line/circular, spline/line, and spline/spline tangency behavior | Passed in the focused contract run. |
| CLI, Automation, and Agent contract boundaries | Passed in the focused contract run. |
| Focused forward-contract run | Passed: 13 of 13 tests; count verified from the Xcode result bundle. |
| Full `RupaCoreTests` execution | Failed with a broad failure list; it remains an open integration gate. |
| Full Swift-CAD `CADGeometry-Tests` execution | Failed: 230 of 242 tests passed and 12 failed; count verified from the Xcode result bundle. |
| Separated cone-torus exact-empty contract | Passed in the focused run and the full Geometry run; the obsolete unsupported-capability expectation was removed. |
| General revolved-surface contracts | Passed in the focused run and the full Geometry run; exact curve results validate residuals and both surface parameter curves. |

## Remaining P0 completion gates

1. Close the exact-kernel Geometry, Topology, Modeling, Kernel, and Exchange regressions recorded by the Swift-CAD checkpoint.
2. Remove development-envelope completion exemptions for supported public inputs.
3. Close the full-suite failures and record the normative same-revision gate set.

## Verification

Run `python3 Scripts/check_p0_forward_integration.py`. It verifies the Rupa
integration ancestor, exact dependency revisions, clean dependency worktrees,
and the local/remote package dependency declarations used by the build.
