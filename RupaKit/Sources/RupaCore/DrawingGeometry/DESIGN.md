# Drawing Geometry

## Purpose and Scope
Child of [RupaCore](../DESIGN.md). Direct children: [DrawingSilhouettes](DrawingSilhouettes/DESIGN.md), [DrawingGlyphs](DrawingGlyphs/DESIGN.md), [DrawingPages](DrawingPages/DESIGN.md). Integrates the current saved
view and evaluated document with SwiftCAD original B-rep geometric projection.
Complete visibility, scene occurrences, material sections and page export remain
required downstream composition; edge-only publication does not complete them.

## Responsibilities and Boundaries
DrawingProjectionService.generateGeometricEdges owns saved-view admission and
current-source handoff. SwiftCAD DocumentDrawing owns exact source equality;
CADKernel BRepDrawing owns topology traversal. Existing DrawingProjectionPage,
ExportStyle and annotation layout retain page/style ownership.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [DrawingSilhouettes](DrawingSilhouettes/DESIGN.md) | child | original placed contour receipt | Shares page admission | Normal-zero contours do not imply occlusion classification |
| [DrawingPages](DrawingPages/DESIGN.md) | child | single-map original page composition | Publishes current curves and dimensions | Same caller ledger through writer |
| [DrawingGlyphs](DrawingGlyphs/DESIGN.md) | child | explicit Native font outlines | Preserves actual glyph geometry | Font matching is fallible |
| [RupaCore](../DESIGN.md) | parent | DesignDocument/saved views | Supplies current source | Display generation alone is insufficient |
| [SwiftCAD DocumentDrawing](/Users/1amageek/.codex/worktrees/occt-parity/swift-CAD/Sources/SwiftCAD/DocumentDrawing/DESIGN.md) | depends on | retained original geometry publication | Supplies projected curve uses | Preserve native parameters and SI units |

## Architecture
```text
DrawingProjectionQuery -> validated saved view -> immutable orthographic frame
 -> current exact evaluation -> DocumentDrawingProjector -> retained curves
 -> complete drawing/page/export publication
```

## Contracts and Invariants

`DrawingOccurrenceProjecting` composes original projected-use receipts with
`SceneNodeHierarchy.resolvedOccurrences`. Each visible CAD occurrence retains
its original occurrence, source node, feature and body IDs. Every actual body
of a feature is included. The original source curve is mapped through the
validated original affine placement and then projected at the same native
parameter; nonuniform scale, reflection and repetition require no fitting.
Saved-view explicit visibility is applied to both presenting and source nodes.
The caller separately bounds original uses, occurrences and published uses;
output capacity is admitted before creating a retained affine image. The result
retains the complete original document and projection snapshot and rejects stale
reuse. It is geometric publication; clipping, section and hidden-line partition
must consume the retained saved view separately before complete page output.
The public original-geometry result preserves B-rep provenance and complete
curve parameter laws. It never returns triangle boundaries as curve evidence.
The saved view supplies target/right/normal; page scale is applied only by the
page/export owner. Source mismatches and resource failures propagate. The legacy
mesh drawing route remains explicitly incomplete for D1/D2.

## Verification and Change Impact
After all source implementation, execute saved-view projection through the
application and export port, including source changes, closed/reversed curves,
occurrence placements, visibility/section material holes and caller refusals.
A source result is not GPU, runtime or complete drawing evidence.

The geometric section entry admits the current complete document and delegates
the supplied orthonormal section frame to DocumentDrawingSectioner. It retains
all original body/face/material contact components. Scene occurrence placement,
material-region assembly and page hatching are still separate pending publication
paths; they must not treat unassembled components as a closed material region.

The public geometric hatch entry admits the current exact evaluation and
retained original section, forwarding all caller capacities to the SwiftCAD
facade. It returns original-solid classified section spans with body/material
identity and applies no page/unit conversion. Closed contour nesting and complete
page composition remain distinct publication responsibilities.

The geometric region entry consumes the same current original section and
publishes exact material patch loops from the kernel halfedge arrangement,
including inner loops and multiple connected regions. The page owner projects
these original curves and applies scale once; raw section components are no
longer a surrogate for assembled region contours.

DrawingProjectionService.generateGeometricSilhouettes admits the current complete
CAD source and exact evaluation before forwarding the original silhouette frame,
all caller capacities and cumulative usage to SwiftCAD. Contacts and non-discrete
zero face domains stay explicit. Publication of this result does not replace the
remaining complete hidden-line and boundary-event algorithms.

Placed exchange publication is the kernel `BRepDrawingPlacedProjection` receipt.
The application supplies each visible occurrence/body's authored affine law;
`DefaultBRepDrawingPlacer` owns original curve image construction. The application
maps that immutable lower use back to current occurrence/source-node/feature
provenance. `DrawingOccurrenceProjection.exchangeProjection` is consumed by
CADExchange after whole current scene/document admission, with no second curve
fitting or placement reconstruction. Source-body fan-out preserves the caller
occurrence bound and derives placement admission from that bound and original
body count with checked arithmetic. Page scale remains exclusively downstream.

`DrawingProjectionService.writePlacedGeometricEdges` is the public sink path from
current saved view/scene to placed original geometry and DXF/SVG/PDF exchange.
It resolves one exact evaluation, validates the complete retained scene receipt,
and passes the same current evaluation to the lower format producer. Caller
conversion/page options and exchange limits are forwarded unchanged; this
geometric export remains unclassified until complete hidden-line composition.

The geometric section service accepts optional explicit original body IDs and
forwards them unchanged to DocumentDrawingSectioner. Omission preserves the
original all-body route. This scoped result is not a placed-world section receipt.

Original geometric annotation publication resolves topology from the same retained
exact evaluation as the drawing. `TopologySnapshotService` accepts that complete
evaluation with original document/tolerance equality and B-rep validation, avoiding
another source evaluation. Drawing annotations use the existing original anchor,
metric and layout producers; unresolved required anchors or missing metric values
fail this strict geometric entry instead of publishing a name as a dimension.
Curvature combs remain a viewport analysis and do not fabricate a drawing dimension.
Caller annotation capacity is admitted before resolving and laying out labels.

Exact drawing resolution honors its injected exact evaluator, or the injected
pipeline's public exact operation when no exact evaluator is supplied. Explicit
providers take precedence over cached default evaluation; without an override,
existing current/incremental reuse remains unchanged. Topology summary consumes
the retained evaluation's original tolerance, preserving explicit evaluator
configuration instead of imposing the document's default tolerance on providers.

The strict geometric page entry uses one exact evaluation for original placed
curve uses and dimension receipts, then validates both before composition. A
retained page validates complete current scene/document/evaluation at the sink.
The caller supplies explicit paper geometry/font/rounding allowances; page
composition and actual format writing share one cumulative usage. No visibility
classification or section provenance is inferred from geometric edge presence.

The unplaced original geometric-edge entry follows the same explicit exact-provider
precedence as placed/page entries; it does not discard an injected exact evaluator
or invoke rendering mesh evaluation to obtain geometric projection authority.

### Current occurrence placement and section composition

`DrawingOccurrencePlacementResolving` is the shared original scene/body authority
for projected edges and placed sections. It resolves complete current lineage,
source node, visible occurrence and authored affine columns once, preserving
multiple outputs of each feature and repeated component instances. Section
composition uses explicit total placement/source-entity/preparation-work/component
capacities. Each body's world source law is retained separately from complete
original evaluation freshness, and output remains bound to the whole original
DesignDocument scene snapshot. No inverse-plane approximation owns clipping.
Complete bounded OriginalImage/world-plane SSI remains a lower source gap;
assembled results cannot replace that proof or claim hidden-line completeness.

### Existing command publication

Both original `generateDrawingProjection` command forms call the current exact
placed-curve producer. The legacy result carrier retains original curve laws once
per topological use, source occurrence/body/edge provenance and directed native
parameters; each published chord references that retained use and its original
parameter endpoints. One whole-invocation exchange usage bounds original curve
linearization and output retention. Exceeding stroke capacity is a typed failure,
not a truncated successful drawing. Dimension anchors use the same canonical
projection frame as the original curves, so paper mapping cannot mirror only one
of geometry and annotation.

The currently incomplete full command domains are explicitly refused/marked:
selected source sections need their original section-to-command composition,
and visibility needs complete original ray/trim event partitions. Geometric
strokes are unclassified. The obsolete mesh producer remains private deprecated
for source transition and cannot be selected by these commands.

### Original Hierarchy Placement Words
Drawing resolves original occurrences, retaining node/root, instance and parent
raw Transform3D factors separately in application order. Full binary affine
columns are copied directly from each authored matrix, never from numeric
world/local composition. The immutable original word owns geometric projection;
ScenePlacement remains a display binding candidate. Legacy drawing factories
retain their cancellation-only no-new-ceiling policy; explicit caller algebra
admission is available through the original word builder and must be shared by
new bounded composition. No finite whole invocation receipt is inferred from
legacy factories. Deferred evidence covers nested nonuniform/reflected instance
source order, multi-body provenance and current whole-scene freshness.

### Selected Original Cutting Planes
DrawingCuttingSupportResolving resolves every explicitly selected construction
node occurrence from the current saved view and whole source scene. Local XY/YZ/ZX
planes retain canonical authored axes; an explicit Plane3D retains all authored
fields. It concatenates original node/root/instance/parent factors and publishes
BRepDrawingCuttingSupport under the supplied DrawingExchangeUsage. Numeric world
plane normals and composed matrices never own this source. Selected cutting
planes are controlled by saved-view section state, independently of decoration
visibility. Duplicate/missing/foreign source references fail; repeated component
occurrences retain distinct source identity. Original hierarchy expansion byte
admission remains an explicit lower source gap until the read model exposes the
same caller callback. This port is not full section or page completion.

The selected-cut overload of DrawingOccurrenceSectioning consumes original local
cutting supports and each current visible original body placement. It uses one
residual work/retained-entity/byte receipt across all support/body pairs. Returned
sections retain whole scene, saved view and exact original evaluation. Output
projection is independent of cutting UV. Original source/subdivision/algebra
capabilities pass unchanged; all metadata and original placements are checked
before publication. Aggregate body/sewing bytes and hierarchy callback gaps
remain explicit source dependencies, not relaxed caller capacities.

The public original-cutting hatch command requires explicit preparation work and
bytes plus distinct source/subdivision/algebra capabilities. It resolves the
current exact evaluation once and forwards the immutable section identity
through DocumentDrawingHatcher. Returned spans use original cutting UV and
publication uses their original world curve. Existing legacy frame hatch
remains a separate authored-frame contract; no limits are inferred to silently
upgrade that invocation. Complete current drawing command composition and
aggregate lower callbacks remain required before full D3/D4 closure.

Selected-section command preparation receipts include original cutting-support
factory work/storage and the later occurrence-section preparation contribution.
The remaining allowance forwarded to the second phase is never reset, and
returned aggregate counters are checked against the original caller limits.
Topology entity capacity remains distinct from exact algebra/source visit counts.

The additive selected-section overload accepts the same live `DrawingExchangeUsage` used by page/glyph/format composition. Original support preparation consumes that owner directly; bounded section residual receipts are attached before another phase. Lower live SSI/classifier/byte propagation is still required for full aggregate concurrent admission.

The public `generateGeometricSilhouettes` route resolves the same current saved
view and placed original edge receipt, then consumes every actual placement
through one DrawingSilhouettePreparation. Its returned contact/curve/atlas/zero
domain receipt is original contour geometry, not a foreground-depth visibility
result. The page publisher must retain all those source categories.

### Bounded Source Occurrence Expansion
The additive SceneNodeHierarchy.originalDrawingOccurrences static operation walks
original product metadata directly under the same DrawingExchangeUsage. It
preserves the existing hierarchy's root/child/definition order and owned root
placement semantics, while retaining only original factor words, identity and
visibility. It does not compute numeric local/world matrix candidates. Original
forest ownership, complete reachability and recursive component definitions are
checked before publishing the complete array. Each source visit and actual
capacity/string/factor retention is paid before allocation. Source nesting uses
the caller's maximumNesting independently from geometry/algebra capabilities.
The legacy instance read model and frozen viewport routes are unchanged. Sketch
radial publication consumes this source operation rather than preparing a legacy
whole hierarchy outside its page ledger. Deferred tests compare occurrence IDs,
factor order, root overrides, nested instances and visibility with the legacy
valid-source route, and exercise lowered budgets/cancellation/cycles.
