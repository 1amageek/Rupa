# Known Issues Backlog

Deferred defects and gaps discovered during implementation verification. Items here are
acknowledged but intentionally not fixed yet; promote an item into active work when it
blocks correctness or an agent workflow. Fixed items must be removed.

Severity: `correctness` (wrong results or crash) > `workflow` (blocks a conventional
workflow) > `ergonomics` (usable but hostile) > `hardening` (defense in depth).

## Correctness

| ID | Issue | Detail | Found |
|---|---|---|---|
| C-2 | Ring revolve fails to tessellate under `ModelingTolerance.standard` | `DocumentEvaluator().evaluate` throws `ExportError.invalidMesh("Mesh normal … does not agree with triangle … winding.")` for the annulus ring: quarter-annulus cap polygons (~3k arc samples) are ear-clipped into sliver triangles. Rupa only survives because `workspaceScaleAware` clamps distance ≥ 1e-8. Cap tessellation should use ring strips or coarser cap sampling instead of ear-clipping mega-polygons. | 2026-07-06 revolve audit |
| C-3 | keep-tools sweep boolean: kept tool body invisible to measurement | With `keepTools == true` the kernel keeps target + remapped tool + result (3 bodies), but `MeasurementService.evaluatedBodyID` only resolves `[.feature, .generated(body)]` names; the tool body (`.subshape("tool")`) is never measured, so totals under-count by the tool volume. | 2026-07-06 boolean audit |
| C-4 | Far-origin loop stitching can drop valid profiles | `MeasurementService` `isClose` compares point gaps against `tolerance.distance`, but at ~1e12 coordinates the coordinate ulp (~2.4e-4 m) exceeds fine CAD tolerances, so truly-coincident endpoints can fail to stitch and the profile is silently skipped. Only bites when tolerance < coordinate ulp. | 2026-07-06 far-origin audit |
| C-7 | Line-chain slot caps store swapped coincident constraints | `SlotProfileBuilder.swift:242-253,270-280` pair `.lineEnd(left) ↔ .arcStart(cap)` / `.arcEnd(cap) ↔ .lineStart(right)`, binding points a full slot-width apart (curve-chain slots pair correctly). No solver runs at commit, so the false constraints land silently and poison later constraint-driven edits. Fix: swap to arcEnd/arcStart pairing as in `buildCurveChainSlot`. | 2026-07-07 sketch-tools audit |
| C-8 | Spline refit with keepsCorners never verifies its tolerance contract | `SketchCurveRebuildDeviation` evaluates each candidate at raw global fractions without remapping into the candidate's local domain, so per-interval deviation is garbage; the loop silently falls back to the original span while reporting success, and the reported max deviation is misaligned. | 2026-07-07 sketch-tools audit |
| C-12 | Trimmed B-spline faces with two or more holes always fail | The per-hole bridging loop feeds the already-bridged polygon (with corridor edges) back into simple-polygon validation, which reports the corridor as self-intersecting; ≥2 holes deterministically throw `unsupportedFace`. Planar caps reject even one circular hole. | 2026-07-07 tessellator audit |

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

## Numerical Robustness Risks

| ID | Issue | Detail | Found |
|---|---|---|---|
| R-1 | Loft/extrude BRep fan volume trusted over the mesh for twisted ruled faces | `evaluatedBRepVolume` gates on line-only EDGES, but ruled loft side faces with non-coplanar corners are bilinear surfaces; the flat-polygon fan silently takes precedence over the accurate mesh volume. Frustum-class (planar) lofts unaffected. | 2026-07-07 loft audit |
| R-2 | Loft boundary-progress resampling cuts corners silently | `sampledClosedRing` resamples the lower-vertex-count section by perimeter fraction; samples need not land on profile corners, deviating from the drawn profile with no diagnostic when section vertex counts differ. | 2026-07-07 loft audit |
| R-3 | Component renderable check ignores `isVisible` | `sceneNodeTreeContainsRenderableNode` counts hidden nested profile sketches as renderable; whether component instances re-show hidden sketches in the viewport is unverified. | 2026-07-07 persistence audit |
| R-4 | Micro-scale absolute epsilons in curve intersection/join/slot math | Absolute 1e-14 discriminant epsilon collapses ≲50 µm line×circle crossings into a bogus tangent point; 1e-12 m² collinearity floor makes ≤10 µm bent lines join as straight; slot builders reuse 1e-12 m distance tolerance as m² cross and fraction epsilons and require 0.01 nm chain coincidence. Fix direction: relative/dimension-correct epsilons (`ModelingTolerance.angle`, length-scaled floors). | 2026-07-07 sketch-tools audit |
| R-6 | Cut drops sub-tolerance spline sample chords | Chords < 1e-6 m are silently discarded, so cutters crossing Bezier segments shorter than ~64 µm are missed and the curve is cut at fewer points than actual. | 2026-07-07 sketch-tools audit |
| R-7 | Slot offset-arc trim can wrap to a near-full circle | Interior joins landing just past an offset arc's far endpoint wrap `directedAngleSpan` to ~2π−ε and pass the arc guard, silently inflating a trimmed arc. Validate trimmed span against the original span. | 2026-07-07 sketch-tools audit |
| R-8 | Splitting a tangent-reference line leaves `.splineEndpointTangent` on the wrong piece | Split migrates only the spline side; when the split entity is the referenced line and the attachment endpoint moves to the new entity, the constraint keeps naming the old line. | 2026-07-07 sketch-tools audit |
| R-9 | Dimensional-category tolerance mismatches in split/fillet/corner math | Split fraction bounded by a metre tolerance (also inconsistent with Cut's 1e-10 filter); `tan/sin(angle/2)` compared to distance tolerance; distance tolerance used as angular tolerance in `storageAngle`. Loud but misleading failures at extreme scales. | 2026-07-07 sketch-tools audit |
| R-10 | Ear-clipping sliver gates use absolute area epsilons | The C-2 root cause: ear convex/containment/adoption predicates compare 3D crosses to 1e-12 absolute, so slivers whose normal is rounding noise pass and `Mesh.validate` fails (or all ears are rejected). Durable fix: ring-strip annular caps, relative sliver gates, sagitta-based simplification, or monotone decomposition. Also O(n²)-O(n³) on ~3k-point cap polygons. | 2026-07-07 tessellator audit |
| R-11 | Circle tessellation cap (8192) silently exceeds stated tolerance beyond R≈14 m | Splines throw in the same condition; circles silently degrade (sag ~74x tolerance at R=1000 m), weakening loop self-intersection validation and oblique-extrude geometry. Throw or derive the cap from tolerance. | 2026-07-07 profile audit |
| R-12 | Oblique extrude silently falls back from exact boundaries to tessellated polylines | Non-normal directions drop `exactBoundarySegments` with no diagnostic; a circle extruded obliquely becomes a polyhedral prism. Emit a diagnostic or gate behind an option. | 2026-07-07 profile audit |
| R-13 | Profile indices are order-of-geometry unstable | Canonical loop ordering is tolerance-fuzzy (breaks strict weak ordering) and adding an unrelated loop reindexes existing profiles, silently retargeting `ProfileReference(profileIndex:)`. Resolve references by stable loop identity instead. | 2026-07-07 profile audit |
| R-14 | Sweep frame transport falls back discontinuously | When the path turns into the previous frame normal, projection transport silently snaps to a fallback normal (up to ~90 degrees of roll in one span), producing twisted spans. Use rotation-minimizing double-reflection or reject beyond an angle threshold. | 2026-07-07 sweep/boolean audit |
| R-15 | Curved-sweep sections are placed by absolute sketch-plane coordinates | Off-origin profiles teleport between the exact straight-extrude plan (extrudes in place) and curved plans (re-express plane-origin offsets in every frame), and lose precision at site scale. Rebase sections about a consistent anchor in all plans. | 2026-07-07 sweep/boolean audit |
| R-16 | Straight-path twist undersamples to a single span | Frame density comes only from path geometry (a line yields 2 frames), so twist 90-180 degrees folds into one span as a self-intersecting bowtie with no diagnostics; twist is unbounded. Densify by twist/scale rate. | 2026-07-07 sweep/boolean audit |
| R-17 | Tessellator silently skips failed triangles | `appendCylinderFace`/`appendBSplineGridFace` ignore append failures (degenerate quads vanish; compaction hides unreferenced vertices from validation), and cylinder strip pairing is never verified as axis-aligned. Count failures and throw past a threshold. | 2026-07-07 tessellator audit |

## Hardening

| ID | Issue | Detail | Found |
|---|---|---|---|
| H-2 | Supersede classification must stay in lockstep with new boolean kinds | `FeatureOperation+RupaClassification.supersededBodyFeatureIDs` enumerates kinds; future extrude/revolve/loft boolean targets will re-open the sweep double-count bug class unless extended together. Consider an exhaustive-by-construction design. | 2026-07-06 boolean audit |
| H-4 | Swift Testing free functions cannot be run individually via xcodebuild | `-only-testing:Target/function` silently matches nothing for top-level `@Test` functions; verification must run whole targets. Wrap new tests in `@Suite` structs or add a filtering mechanism. | test-run audit |
| H-5 | `AutomationResult` documented shape diverges from implementation | SPEC §Automation Results fields (`success`, `mode`, `generationBefore/After`, `outputs`, `error`) have no matching type; the implemented shape is the response envelope. Decide schema before exposing automation publicly. | SPEC gap audit |
| H-6 | Named spec abstractions absent | `DocumentLock`, `FileChangeBroadcaster`, `ReferenceResolver`, `AgentSchema` named by SPEC do not exist; functionality is distributed. Implement or amend SPEC. | SPEC gap audit |
| H-7 | Click-placed box has no upper size clamp | Placement tracks the visible grid cell by design; extreme zoom-out yields proportionally huge cubes. Click depth (= visible cell) also differs from drag depth (`sketchDepthMeters`). | box-scale review |
