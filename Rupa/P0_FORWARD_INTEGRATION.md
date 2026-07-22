# P0 Forward Contract Integration

## Decision

Rupa revision `0c5868990c9c4bae2968fba324431a9a5fee5f1b` adopts the forward
Swift-CAD contract preserved at revision
`288d5cd2d618c6f8db2f147ba8aa2dfd2e8157d3`. The reproducible repository
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
| Surface trim add, replace, and remove behavior | Passed |
| Stable edge offset and explicit gap-fill rejection | Passed |
| Line/circular, spline/line, and spline/spline tangency behavior | Passed |
| CLI, Automation, and Agent contract boundaries | Passed |
| Full `RupaCoreTests` execution | Inconclusive: the Xcode/Swift Testing runner reported a broad failure list without assertion diagnostics; focused tests passed. |

## Remaining P0 completion gates

1. Close the exact-kernel Geometry, Topology, Modeling, Kernel, and Exchange regressions recorded by the Swift-CAD checkpoint.
2. Remove development-envelope completion exemptions for supported public inputs.
3. Run and record the normative same-revision gate set without the current full-suite runner anomaly.

## Verification

Run `python3 Scripts/check_p0_forward_integration.py`. It verifies the Rupa
integration ancestor, exact dependency revisions, clean dependency worktrees,
and the local/remote package dependency declarations used by the build.
