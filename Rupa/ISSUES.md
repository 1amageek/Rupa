# Known Issues Backlog

Deferred defects and gaps discovered during implementation verification. Items here are
acknowledged but intentionally not fixed yet; promote an item into active work when it
blocks correctness or an agent workflow. Fixed items must be removed.

Severity: `correctness` (wrong results or crash) > `workflow` (blocks a conventional
workflow) > `ergonomics` (usable but hostile) > `hardening` (defense in depth).

## Correctness

| ID | Issue | Detail | Found |
|---|---|---|---|
| C-1 | Extrude concave-arc side walls are meshed inside-out | `swift-CAD/Sources/CADKernel/PlanarExtrudeFeatureEvaluator.swift` `.circularArc` branch of `addSideFace` emits `.cylinder` faces with default `.forward` orientation; a profile boundary with a concave arc (material outside the arc circle) gets an inward-oriented wall — the same defect class as the fixed revolve inner wall, silently inflating mesh volume. Convex arcs happen to be correct. Fix shape: derive material side from arc sweep direction vs profile winding and set `Face.orientation`. | 2026-07-06 revolve audit |
| C-2 | Ring revolve fails to tessellate under `ModelingTolerance.standard` | `DocumentEvaluator().evaluate` throws `ExportError.invalidMesh("Mesh normal … does not agree with triangle … winding.")` for the annulus ring: quarter-annulus cap polygons (~3k arc samples) are ear-clipped into sliver triangles. Rupa only survives because `workspaceScaleAware` clamps distance ≥ 1e-8. Cap tessellation should use ring strips or coarser cap sampling instead of ear-clipping mega-polygons. | 2026-07-06 revolve audit |
| C-3 | keep-tools sweep boolean: kept tool body invisible to measurement | With `keepTools == true` the kernel keeps target + remapped tool + result (3 bodies), but `MeasurementService.evaluatedBodyID` only resolves `[.feature, .generated(body)]` names; the tool body (`.subshape("tool")`) is never measured, so totals under-count by the tool volume. | 2026-07-06 boolean audit |
| C-4 | Far-origin loop stitching can drop valid profiles | `MeasurementService` `isClose` compares point gaps against `tolerance.distance`, but at ~1e12 coordinates the coordinate ulp (~2.4e-4 m) exceeds fine CAD tolerances, so truly-coincident endpoints can fail to stitch and the profile is silently skipped. Only bites when tolerance < coordinate ulp. | 2026-07-06 far-origin audit |

## Workflow

| ID | Issue | Detail | Found |
|---|---|---|---|
| W-1 | Sketch commands cannot reference a saved construction plane by ID | Plane-less creation now routes through the ACTIVE plane, but there is no `--construction-plane-id` to sketch on a specific saved plane without activating it first. | 2026-07-06 CLI verification |
| W-2 | `rupa feature suppress` missing | SPEC-required command group; needs a Core feature-suppression command first. | SPEC gap audit |
| W-3 | `--in-place` / `--output` file-mode flags missing | SPEC CLI Modes table lists them; semantics overlap with the unresolved `--force` open decision. | SPEC gap audit |
| W-4 | Live/auto batch is non-atomic | Documented in `rupa batch` help: per-command commits, partial application on mid-batch failure. A server-side transactional batch (AgentRequest.executeBatch) would close it. | batch review |
| W-5 | MCP bridge not implemented | The protocol names MCP clients as a target consumer; no bridge exists, so vision-LLM agents cannot consume capabilities/renders directly. | agent harness review |
| W-6 | One-shot render command missing | Observing the model requires saved-view + projection (two steps). A `rupa view render` (camera preset -> SVG/PNG, no saved view) would give agents a single observation step. | agent harness review |

## Ergonomics

| ID | Issue | Detail | Found |
|---|---|---|---|
| E-1 | SelectionTarget JSON leaks the synthesized `_0` key | Agents must write `{"component":{"edge":{"_0":"…"}}}`; the Swift-internal key is an implementation detail in a public contract. | 2026-07-06 CLI verification |
| E-2 | Sketch-plane 2D→3D axis mapping undocumented | `--plane zx` help does not say which world axes u/v map to; path directions are easy to get wrong (verified by mis-sweeping a boolean tool). | 2026-07-06 CLI verification |
| E-3 | Same-plane loft rejection message is cryptic | `Loft produced unsupported or invalid geometry: openShell(UUID)` — typed but unactionable; should say the sections are coplanar. | 2026-07-06 CLI verification |
| E-4 | `--expected-generation` silently overrides the batch file's embedded value | Precedence is intentional but only documented in a code comment, not the flag help. | batch review |
| E-5 | Empty-batch handling differs between file and live at the `runBatch` API | File mode returns an empty response; live throws. CLI guards it, but the public API contract is inconsistent. | batch review |
| E-6 | Selection-scope measurement of a superseded body is silent | Selecting a boolean-replaced target reports its pre-boolean analytic volume with no diagnostic (supersede filtering is deliberately disabled under selection). Needs at least an info diagnostic. | 2026-07-06 boolean audit |

## Hardening

| ID | Issue | Detail | Found |
|---|---|---|---|
| H-1 | Mixed-orientation meshes are not detected | `evaluatedMeshMeasurement` applies `abs(signedVolume)`; a mesh with flipped subsets silently measures wrong. For a closed mesh the oriented triangle-area sum is ~0; a large residual should surface as a measurement error. | 2026-07-06 revolve audit |
| H-2 | Supersede classification must stay in lockstep with new boolean kinds | `FeatureOperation+RupaClassification.supersededBodyFeatureIDs` enumerates kinds; future extrude/revolve/loft boolean targets will re-open the sweep double-count bug class unless extended together. Consider an exhaustive-by-construction design. | 2026-07-06 boolean audit |
| H-3 | Standalone boolean has no measurement regression test | Sweep boolean supersede is now covered; the standalone `.boolean` path (which worked) still has no measure-totals test pinning it. | 2026-07-06 boolean audit |
| H-4 | Swift Testing free functions cannot be run individually via xcodebuild | `-only-testing:Target/function` silently matches nothing for top-level `@Test` functions; verification must run whole targets. Wrap new tests in `@Suite` structs or add a filtering mechanism. | test-run audit |
| H-5 | `AutomationResult` documented shape diverges from implementation | SPEC §Automation Results fields (`success`, `mode`, `generationBefore/After`, `outputs`, `error`) have no matching type; the implemented shape is the response envelope. Decide schema before exposing automation publicly. | SPEC gap audit |
| H-6 | Named spec abstractions absent | `DocumentLock`, `FileChangeBroadcaster`, `ReferenceResolver`, `AgentSchema` named by SPEC do not exist; functionality is distributed. Implement or amend SPEC. | SPEC gap audit |
| H-7 | Click-placed box has no upper size clamp | Placement tracks the visible grid cell by design; extreme zoom-out yields proportionally huge cubes. Click depth (= visible cell) also differs from drag depth (`sketchDepthMeters`). | box-scale review |
