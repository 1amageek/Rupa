# Analysis Strategy

## Task Structure

The audit separates four questions: what has real implementation, what reaches the running app, what executes successfully today, and what remains before a release claim is possible.

## Key Layers and Categories

| Layer | Category | Audit focus |
|---|---|---|
| Context | Repository state | repositories, branches, dirty worktrees, normative status documents |
| Situation | Universal foundation | capability registry, mesh source, project model, evaluation, viewport snapshot |
| Operation | Verification | build and targeted test execution with timeout |
| Problem | Integration blockers | Rupa/Swift-CAD API drift and unused universal app path |
| Issue | Kernel correctness | exact intersection, topology, sweep, trim, and numerical regressions |
| Solution | Recovery sequence | restore compatibility, stabilize kernel, then wire universal path |
| Outcome | Release readiness | whether current state can support a conformance or release claim |

## Decomposition Strategy

- Structural decomposition by repository and module boundary.
- Contrastive analysis between declared status and executable evidence.
- Funnel analysis from authored source through evaluation, viewport, app consumption, and tests.
- Root-cause grouping of failures by API drift, geometry certification, topology invariants, and test infrastructure.

## Evidence Report Design

The report uses three primary visual patterns: implementation slice maturity, executed test outcomes, and a readiness flow showing the blocked integration gate. Completion percentage is intentionally not synthesized because the project contracts define binary gates and prohibit weighted completion claims.

## Chartable Data Requirements

- Universal plan status counts by declared slice state.
- Swift-CAD capability counts and gate counts.
- Executed passed/failed test counts by target.
- Worktree change counts for reproducibility risk.

## Revision History

- 2026-07-22: Initial strategy created after repository scan and before final synthesis.

