# P0 Integration Baseline

## Decision

Rupa integration and the preserved exact-kernel work in progress use separate
revision sets.

The integration baseline is the three-repository tuple recorded in
`P0_INTEGRATION_BASELINE.json`. Rupa may advance from the recorded minimum
revision, while the local `swift-CAD` and `swift-OpenUSD` dependencies must match
their recorded revisions exactly and have clean worktrees.

The exact-kernel work in progress is preserved separately at
`swift-CAD` branch `codex/p0-swift-cad-checkpoint`, revision `288d5cd`. That
checkpoint is intentionally not accepted by the integration-baseline checker.

## Rationale

RupaKit resolves `swift-CAD` through a local path, and that package resolves
`swift-OpenUSD` through another local path. A Rupa commit alone therefore cannot
identify the implementation that is compiled.

The selected integration tuple retains the `PersistentName` and
`SelectionReference.topology` contract currently consumed by Rupa. Later
Swift-CAD revisions introduce `SubshapeID`, `StableSubshapeReference`, explicit
modeling tolerance, and exact topology signatures. Those changes require a
downstream persistence and selection migration and are not compatibility fixes.

## Verification

The tuple has the following executed evidence:

| Scope | Result |
|---|---|
| Full RupaKit package build | Passed |
| Generated topology selection round trip | 1 passed, 0 failed |
| Typed mesh selection tests | 2 passed, 0 failed |

This evidence establishes a recoverable integration baseline. It does not claim
that every RupaKit or historical Swift-CAD test is green.

## Enforcement

Run `python3 Scripts/check_p0_integration_baseline.py` before using the baseline
for integration verification. A revision mismatch, missing repository, or dirty
local dependency returns a nonzero exit status with an explicit diagnostic.

## Next contract migration

The later stable-subshape contract should move downstream in a dedicated change
set covering selection serialization, generated-body identity, material binding,
measurement, surface references, viewport selection, and UI state. It must not be
implemented as a silent fallback to string-based persistent names.
