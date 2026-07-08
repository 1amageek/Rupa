# Known Issues Backlog

Deferred defects and gaps discovered during implementation verification. Items here are
acknowledged but intentionally not fixed yet; promote an item into active work when it
blocks correctness or an agent workflow. Fixed items must be removed.

Severity: `correctness` (wrong results or crash) > `workflow` (blocks a conventional
workflow) > `ergonomics` (usable but hostile) > `hardening` (defense in depth).

## Correctness

| ID | Issue | Detail | Found |
|---|---|---|---|

## Workflow

| ID | Issue | Detail | Found |
|---|---|---|---|
| W-3 | Legacy inline CLI commands still lack shared `--output` file-mode support | `CLIWriteDocumentOptions` machine-facing mutation commands now route through `CLIDocumentWritePolicy` with `.swcad`/existing-output/live-session validation; older inline commands in `CLICommand.swift` still need migration to the shared write target contract. | SPEC gap audit |
| W-4 | Live/auto batch is non-atomic | Documented in `rupa batch` help: per-command commits, partial application on mid-batch failure. A server-side transactional batch (AgentRequest.executeBatch) would close it. | batch review |
| W-5 | MCP bridge not implemented | The protocol names MCP clients as a target consumer; no bridge exists, so vision-LLM agents cannot consume capabilities/renders directly. | agent harness review |

## Ergonomics

| ID | Issue | Detail | Found |
|---|---|---|---|
| E-1 | SelectionTarget JSON leaks the synthesized `_0` key | Agents must write `{"component":{"edge":{"_0":"…"}}}`; the Swift-internal key is an implementation detail in a public contract. | 2026-07-06 CLI verification |
| E-2 | Sketch-plane 2D→3D axis mapping undocumented | `--plane zx` help does not say which world axes u/v map to; path directions are easy to get wrong (verified by mis-sweeping a boolean tool). | 2026-07-06 CLI verification |
| E-3 | Same-plane loft rejection message is cryptic | `Loft produced unsupported or invalid geometry: openShell(UUID)` — typed but unactionable; should say the sections are coplanar. | 2026-07-06 CLI verification |
| E-4 | `--expected-generation` silently overrides the batch file's embedded value | Precedence is intentional but only documented in a code comment, not the flag help. | batch review |
| E-5 | Empty-batch handling differs between file and live at the `runBatch` API | File mode returns an empty response; live throws. CLI guards it, but the public API contract is inconsistent. | batch review |
| E-6 | Selection-scope measurement of a superseded body is silent | Selecting a boolean-replaced target reports its pre-boolean analytic volume with no diagnostic (supersede filtering is deliberately disabled under selection). Needs at least an info diagnostic. | 2026-07-06 boolean audit |

## Numerical Robustness Risks

| ID | Issue | Detail | Found |
|---|---|---|---|
| R-1 | Loft/extrude BRep fan volume trusted over the mesh for twisted ruled faces | `evaluatedBRepVolume` gates on line-only EDGES, but ruled loft side faces with non-coplanar corners are bilinear surfaces; the flat-polygon fan silently takes precedence over the accurate mesh volume. Frustum-class (planar) lofts unaffected. | 2026-07-07 loft audit |
| R-3 | Component renderable check ignores `isVisible` | `sceneNodeTreeContainsRenderableNode` counts hidden nested profile sketches as renderable; whether component instances re-show hidden sketches in the viewport is unverified. | 2026-07-07 persistence audit |
| R-4 | Micro-scale absolute epsilons in curve intersection/join/slot math | Absolute 1e-14 discriminant epsilon collapses ≲50 µm line×circle crossings into a bogus tangent point; 1e-12 m² collinearity floor makes ≤10 µm bent lines join as straight; slot builders reuse 1e-12 m distance tolerance as m² cross and fraction epsilons and require 0.01 nm chain coincidence. Fix direction: relative/dimension-correct epsilons (`ModelingTolerance.angle`, length-scaled floors). | 2026-07-07 sketch-tools audit |
| R-9 | Dimensional-category tolerance mismatches in split/fillet/corner math | Split fraction bounded by a metre tolerance (also inconsistent with Cut's 1e-10 filter); `tan/sin(angle/2)` compared to distance tolerance; distance tolerance used as angular tolerance in `storageAngle`. Loud but misleading failures at extreme scales. | 2026-07-07 sketch-tools audit |
| R-12 | Oblique extrude silently falls back from exact boundaries to tessellated polylines | Non-normal directions drop `exactBoundarySegments` with no diagnostic; a circle extruded obliquely becomes a polyhedral prism. Emit a diagnostic or gate behind an option. | 2026-07-07 profile audit |
| R-13 | Profile indices are order-of-geometry unstable | Canonical loop ordering is tolerance-fuzzy (breaks strict weak ordering) and adding an unrelated loop reindexes existing profiles, silently retargeting `ProfileReference(profileIndex:)`. Resolve references by stable loop identity instead. | 2026-07-07 profile audit |
| R-14 | Sweep frame transport falls back discontinuously | When the path turns into the previous frame normal, projection transport silently snaps to a fallback normal (up to ~90 degrees of roll in one span), producing twisted spans. Use rotation-minimizing double-reflection or reject beyond an angle threshold. | 2026-07-07 sweep/boolean audit |

## UI Consistency

| ID | Issue | Detail | Found |
|---|---|---|---|
| U-1 | Transform gizmo: height translate, rotate, and scale still revert on release | In-plane translation now commits via moveBody (profile-sketch translation, 2026-07-07); height translation, rotation, scaling, vertexMove/faceMove still have no commit path and revert on release. Sketch selection gizmo is drawn but never hit-tested. | 2026-07-07 UI audit |
| U-8 | Interaction selectors still recompute candidate arrays per target class | hover() and beginViewportPress now share one ordered resolver and one ViewportSceneContext per event, but target helpers still rebuild candidate arrays independently; pointer-move performance needs a per-event candidate cache. | 2026-07-07 UI audit |

## Hardening

| ID | Issue | Detail | Found |
|---|---|---|---|
| H-2 | Supersede classification must stay in lockstep with new boolean kinds | `FeatureOperation+RupaClassification.supersededBodyFeatureIDs` enumerates kinds; future extrude/revolve/loft boolean targets will re-open the sweep double-count bug class unless extended together. Consider an exhaustive-by-construction design. | 2026-07-06 boolean audit |
| H-4 | Swift Testing free functions cannot be run individually via xcodebuild | `-only-testing:Target/function` silently matches nothing for top-level `@Test` functions; verification must run whole targets. Wrap new tests in `@Suite` structs or add a filtering mechanism. | test-run audit |
| H-5 | `AutomationResult` documented shape diverges from implementation | SPEC §Automation Results fields (`success`, `mode`, `generationBefore/After`, `outputs`, `error`) have no matching type; the implemented shape is the response envelope. Decide schema before exposing automation publicly. | SPEC gap audit |
| H-6 | Named spec abstractions absent | `DocumentLock`, `FileChangeBroadcaster`, `ReferenceResolver`, `AgentSchema` named by SPEC do not exist; functionality is distributed. Implement or amend SPEC. | SPEC gap audit |
| H-7 | Click-placed box has no upper size clamp | Placement tracks the visible grid cell by design; extreme zoom-out yields proportionally huge cubes. Click depth (= visible cell) also differs from drag depth (`sketchDepthMeters`). | box-scale review |
| H-8 | Surface trim CLI subprocess tests exceed their 60-second limit in full-target runs | `RupaCLITests` full-target verification reached time limits in `cliExecutableSurfaceTrimControlPointCommandMutatesClosedDocumentAsJSON`, `cliExecutableSurfaceTrimControlPointWeightCommandMutatesClosedDocumentAsJSON`, and `cliExecutableSurfaceTrimKnotCommandMutatesClosedDocumentAsJSON`; isolated view-command verification passes. Split or optimize these subprocess tests. | 2026-07-08 CLI verification |
