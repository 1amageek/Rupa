# Topology Editing

## Purpose and Scope

Child of [RupaCore](../DESIGN.md), with no children. Owns the translation of
selected CAD edges into native fillet, chamfer and G2 blend features, and
selected sheet faces into native offset and trim-domain extension features.
It also translates a selected solid face and thickness into native Shell.
Selected sheet faces may identify their entire sheet body for native Thicken.
It owns in-place length-expression edits of the native operations it exposes.

## Responsibilities and Boundaries

Core resolves source identity and preserves occurrence placement. Swift-CAD
constructs and validates the B-rep. This component does not rewrite the source
sketch, approximate a selected edge by a bounding-box corner, or tessellate.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Core](../DESIGN.md) | parent | source transactions | Allocates feature and presentation identities. | Workspace owns publication and Undo. |
| [Modeling UI](../../RupaUI/Modeling/DESIGN.md) | used by | preview/apply | Supplies selected generated edges and a physical amount. | Display subdivisions do not define the operation. |
| [CADModeling](../../../../swift-CAD/Sources/CADModeling/DESIGN.md) | depends on | native edge blend evaluators | Constructs complete topology or fails. | Current single-edge planar envelope remains explicit. |

## Architecture

```text
UI draft -> EditorCommand -> current stable edge reference
    -> native FeatureOperation -> existing feature graph staging
    -> exact candidate evaluation -> Workspace publication / Undo
```

Request values implement the internal `TopologyEditOperation` protocol: each
declares its selection kind and lowers validated source values to one native
FeatureOperation. A single generic preparation path owns lock/staleness checks,
stable-reference resolution and FeatureNodeFactory invocation. Protocol
conformers own no document mutation, evaluation, cache or publication. Existing
ProjectOperating and FeatureEvaluating remain the authority and kernel ports.

## Contracts and Invariants

- FeatureLengthEditing describes and replaces one native operation's editable
  length without owning graph state. The native implementation handles Extrude,
  Fillet, Chamfer, G2 Blend, Shell, Thicken and Sheet Offset. Unsupported
  operations expose no field and reject replacement. Core retains feature ID,
  operands, outputs, name and suppression; graph-stable replacement updates
  expression dependencies. Workspace stages, evaluates and publishes exactly
  as for creation. Invalid units, stale IDs and infeasible geometry fail before
  publication; no representation or occurrence is recreated.
  The store passes its current validated source and retains the graph-stable
  validation transition for incremental evaluation, matching existing dimension
  commands. Stale validation is rejected before mutation.
- The UI reads the same field contract, formats/parses existing expressions,
  and submits a setFeatureLength command through existing preview/apply.
  This length editor does not replace multi-field primitive, sketch or surface
  control editors, and does not claim all feature properties are editable.

- Shell selects one current generated solid face to remove and a positive
  physical thickness above modeling tolerance. The existing native Shell
  evaluator owns orthogonal-hexahedron admission and wall feasibility; the UI
  connection does not claim general curved-solid shell support. Failure leaves
  all source and representation selections unchanged.

- Sheet operations require one current generated face; the kernel validates
  that its body is a single-face sheet. Offset is a signed source-coordinate
  length with magnitude above modeling tolerance. Extend takes finite ordered
  U/V intervals and enlarges the trim within the underlying surface domain;
  it does not extrapolate an unsupported surface. Unsupported geometry fails
  before source publication, using the same transaction as edge treatments.
  Thicken uses the selected face to identify its sheet body, then thickens the
  whole body with the retained positive length expression and explicit side.
  Swift-CAD owns supported sheet geometry, sewing and solid validity. The
  existing representation retargeting changes the geometry role to solid;
  source sheet features, independent representations and occurrence placement
  remain retained. A solid input or invalid thickness fails atomically.

- A request selects exactly one generated edge of an editable body. Unsupported
  multi-edge blends are refused, not partially applied.
- Radius/distance must be finite and greater than modeling tolerance. The
  kernel owns geometric feasibility and never falls back to sketch editing.
- The stable reference is resolved from current exact topology and must belong
  to the selected occurrence. Missing, stale, locked and non-body inputs fail.
- Matching generation-bound evaluation is reused for a direct subshape lookup;
  resolution does not build a whole topology summary or compute surface metrics.
  A missing/stale supplied evaluation uses the existing exact evaluator contract.
- The result updates only the selected modeling CAD representation's output,
  preserving its representation ID, every other retained representation,
  Authored Mesh assets/provenance and purpose selections. ObjectDescriptor owns
  this retargeting; independent-copy representation reidentification is not an
  edit operation. Node identity, children, parent, transform and material remain.
  Trim creation/removal follows the same representation retargeting contract. A consumed
  source body must not remain in the presentation's geometry requests.
  Input feature geometry remains unchanged; the new feature consumes its body.
- SelectionModel's shared compatibility check rejects generated subshapes whose
  feature no longer owns the occurrence. Existing publication pruning removes
  these selected/hovered targets atomically; it does not select an arbitrary
  replacement face or leave the removed Shell opening active.
- Preparation produces a feature transaction, not a successful geometric result.
  CADDocumentStore/Workspace evaluate the staged candidate before successful
  publication and roll back both source and metadata on failure. No duplicate
  candidate evaluation is added inside preparation.
- Rendering prepares the same transaction in a local document and hands it to
  the existing cancellable preview cache; release uses the same native command.
  Generated-edge drag handles and numeric drafts share this native command.
  [Rendering](../../RupaRendering/DESIGN.md) owns pointer-to-source-length
  measurement; neither route reinterprets the edge as a profile corner.

## State, Ownership, and Lifecycle

All values are request-local. No caches, tasks or shared mutable state are added.

## Verification and Change Impact

`Tests/RupaCoreTests/BodyEdgeTreatmentTests.swift` owns all box-edge orientations,
exact cylindrical fillet geometry, chamfer volume, source preservation,
round-trip and invalid-radius/selection atomicity. Modeling draft tests own
command forwarding and UI validation. Workspace integration owns Undo and
preview cancellation. `Tests/RupaCoreTests/SheetSurfaceEditTests.swift` owns signed
offset geometry, trim extension, source round-trip, Undo and invalid-edit
atomicity. Changes require reviewing Core dispatch and Modeling UI.
`GeometryRepresentationAuthorityTests` verifies that CAD topology edits and trim
changes preserve independently selected Mesh presentation and baked provenance.
`FeatureLengthEditingTests` verifies all seven native length replacements with
actual geometry, retained identities, persistence, Undo, parameter rebinding,
atomic refusal and incremental reuse. `RupaUIPackageTests/FeatureLengthDraftTests`
verifies expression forwarding; the signed App owns history form/preview/apply
and visible Undo verification.
