# Modeling UI

## Purpose and Scope

This component is a child of [RupaUI](../DESIGN.md), with no children. It owns
the editable CAD and Mesh operation forms and their transient preview state,
not source editing or kernel algorithms.

## Responsibilities and Boundaries

Gear creation and reediting use [GearEditing](../../RupaCore/GearEditing/DESIGN.md)
commands and the same preview/apply owner as other feature operations. The form
retains every native dimensional expression; no generated mesh is authored.
Unchanged gear fields retain their original expression trees; only edited text
is parsed. Reformatting a negative constant must not silently rewrite source
operators or parameter references when another field changes.
Gear planning receives the displayed document's modeling tolerance together with
its parameter table. It must not substitute a process-wide tolerance; geometric
feasibility remains the existing evaluator's responsibility.
Creation and history reediting share one workspace-owned gear form and draft.
History forwards the selected source feature rather than retaining a second
gear form. Opening the gear form cancels the previous modeling operation. The workspace
discards its gear form on authority-coordinate changes, preventing a draft
from crossing document replacement or source publication. Cancel clears the
same draft owner as other modeling operations.

The draft retains user text, units, ordered selection and operation options.
Planning produces existing `EditorCommand` values. Workspace remains the only
mutation entry point. Invalid text remains editable and produces a visible
typed error, never a default successful command. MainView owns task sequencing
and passes preview/apply/cancel callbacks; this component owns no task or cache.

Loft section text controls are keyed by scene-node identity, not operand position.
Creation assigns selected operands to sections or guides by scene-node identity.
Both lists preserve selection order after filtering; reordering cannot change an
operand's role. Section controls remain retained when its role changes, but are
not applied to guides. The existing source-coordinate/lock checks cover both roles.
One createLoft command carries the complete references to the existing preview
transaction. Native evaluation owns exact guide contacts and rejects invalid curves.
History guide selection lists earlier, active features with a declared curve
output, excluding section sources and already-selected guides. Existing guides
remain visible even if no longer eligible, so they can be removed. Reordering,
adding and removing guides modifies the same complete setLoft payload; it does
not create a second evaluation or persistence route.
Reordering operands preserves their tension and curve interval. Blank tension
inherits the native operation default. An enabled interval uses finite increasing
native curve parameters and is refused for profile inputs. Draft planning writes
the existing CurveSectionReference and LoftSectionReference; only native evaluation
decides source-domain containment. Curve reversal uses the same identity-keyed
controls and native reference, after interval selection. Profile correspondence
uses the separate native traversal policy. The form never evaluates geometry on hover.
Creation and history editing expose an optional zero-based source start sample
index. Blank selects automatic correspondence; nonnegative integer text is
required otherwise. The native evaluator owns source bounds and exact seam
admission, including reversal/restriction. Clearing a history value removes it.
Creation and history editing share `LoftSectionDraft` parsing and
the native profile traversal policy. Profile inputs expose automatic/forward/
reversed correspondence; curve inputs expose curve reversal and interval instead.
Creation uses the same section resolver for field eligibility and command input.
Invalid source classification is displayed, not converted to a default kind.
Profile section controls expose the zero-based extracted region index. Creation
and history retain the selected index through the same ProfileReference;
nonnegative integer parsing precedes native range and geometry validation.
Extrude, Revolve and Loft share the selected section resolver, preserving explicit
region indexes and rejecting conflicting region/curve choices from one source.

Creation and history editing share `LoftSectionEditorFields` and expose the
Loft default tension as editable dimensionless text. Both creation and history
validate it through `LoftOptions.validate`; section overrides remain independent
and blank section tension inherits this default. Ruled mode retains the value
without applying smooth interpolation. Invalid text never publishes a command.
`LoftFeatureDraft` retains the complete existing native Loft value,
changing only exposed controls and section order; guides,
tangent modes and unexposed options survive unchanged. History editing is keyed by
source FeatureID and does not require a visible scene occurrence for each input.
The history sheet emits `setLoft` into the existing preview/apply owner and closes
when source history changes. It owns text only, not evaluation or document state.
History section insertion and removal edit that same complete source replacement.
Candidates are preceding active features with the requested profile/curve output,
excluding existing sections and guides. The user explicitly chooses the output
kind; exact profile existence and geometry remain native evaluation decisions.
Solid history offers profile sections only. Removing a section removes its text
controls; adding a section initializes controls from its new reference. Invalid
section counts remain editable but cannot produce a preview command.

Feature history uses the parent's [sidebar symbol adapter](../DESIGN.md#sidebar-symbols)
for its status and action icons. Active/suppressed meaning, selection, preview
commands, and busy-state admission remain owned by the existing history view.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RupaUI](../DESIGN.md) | parent | Snapshot presentation and Workspace intent | Composes the form. | Never write a document from a view. |
| [RupaCore](../../RupaCore/DESIGN.md) | depends on | EditorCommand validation, source operations, `WorkspaceScaleDefaults` and `WorkspaceInteractionScaleDefaults` | Owns CAD semantics, topology references and the workspace scale's published defaults. | Scene occurrence transforms are not feature geometry. A default feature size and an interaction step are different quantities. |
| [RupaKit](../../RupaKit/DESIGN.md) | used by parent | Exact preview/commit | Owns publication coordinates. | A preview does not grant commit authority. |

## Architecture

```text
Ordered selection + text fields -> ModelingOperationDraft -> EditorCommand
                                                              |
MainView callbacks -> Workspace preview -> derived preview display
                   -> Workspace perform -> one source commit + Undo
Cancel -> discard draft and preview, no source mutation
```

The parent keeps a single cancellable task and a value-only preview state.
Both operation panels fill their allocated inspector region; their intrinsic form
height must not shrink the Canvas/inspector split. Each panel contains its child
accessibility elements so Preview, Apply and field identifiers remain distinct.
CAD fields use the native grouped form layout so operand descriptions and
instructions receive the full row width instead of a narrow value column.
Interactive regions declare their rectangular content shape.
A new draft invalidates the previous token; late completions cannot restore it.
Taking a ready request for Apply consumes it before awaiting publication, so
repeated button events cannot commit twice. Source or selection publication
invalidates a prepared request; Workspace still validates its exact coordinates.
Preview geometry is displayed in the existing Viewport with supplied-only
evaluation and no source-edit callbacks. Cancel never rolls back an already
published transaction; post-commit errors retain the existing no-replay contract.

Mesh drafts hold persistent source element IDs, a source handle and explicit
source-coordinate lengths. They produce existing Mesh edit plans; the Workspace
Mesh adapter owns handle validation and conversion to source transactions. CAD
Make Editable uses the modeling-purpose conversion contract, never a rendered
triangle copy. Selection is tied to a published scene snapshot and is discarded
when that source changes. Rendering exposes actual source vertices, boundary
edges and faces, not triangulation diagonals as editable edges.

MainView builds the immutable selection outline off MainActor only when the
snapshot, occurrence or selected IDs change. SwiftUI task cancellation propagates
to the worker; a cancelled or stale result cannot publish. Canvas only projects
retained points and segments. Outlines use an orange X-ray overlay, with an
explicit truncation count when the display limit is reached; selected IDs are
never truncated. Numeric field edits do not rebuild selection geometry.
Vertex-position prefill consumes the matching overlay's retained local position.
Draft planning bounds the selected-ID count and validates text and operation
domains; source membership validation belongs to Workspace staging off MainActor.

The feature-history section displays the source graph's ordered features.
Thicken is a standard palette operation using the selected generated sheet
face as a body selector. Its form explains whole-sheet scope and exposes the
native positive, negative and symmetric side values. Thickness uses the same
parameter expression parser and preview/apply path as other topology edits.
Native length-bearing features expose Edit Dimension through Core's
FeatureLengthEditing contract. A transient form retains the expression text,
uses existing parameter parsing/formatting, and forwards setFeatureLength to
the existing history preview/apply flow. Source graph changes dismiss the
form; it never writes directly or allocates a new feature ID.
Suppress/unsuppress and move actions prepare existing source commands, preview
their evaluated candidate and require Apply. Core owns dependency validation;
the UI does not silently move dependent features or suppress a dependency tree.
Named parameter editing remains in the existing document inspector. Selecting a
history row selects its existing scene presentation when available; a suppressed
or unpresented feature remains visible in history without a synthetic scene node.
Each history row presents the feature name, its ordered input/dependency names,
and an explicit suppressed state. Filtering changes visibility only: reorder
commands always carry the complete source graph order and swap adjacent nodes
in that order. Suppression and reorder actions retain the existing preview/apply
path; the row is not a second source graph or a dynamic definition editor.

## Contracts and Invariants

### Surface Creation foundation

Surface Creation is an operation family in the existing modeling draft, not a
new workspace mode or document owner. Its operation picker uses the same
planning, cancellable preview, Apply, Undo and persistence paths as solid edits.
Switching the operation invalidates the previous preview. Sheet creation must
declare a sheet feature output and a surface object role; it must never merely
hide solid caps in the renderer.

The first foundation exposes Plane Surface, sheet Extrude, sheet Sweep, sheet
Loft, hole Patch and Boundary Bridge (G0). Plane Surface is a primitive and is
not the requested boundary Patch or Square. Patch takes one opening seed;
Bridge takes exactly two distinct open edges and retains their orientation and
source dependencies. Both reuse Core's existing boundary-surface transaction.
No operation replaces its input objects. Unsupported geometry fails during
native preview and cannot be applied.

| Requested operation | Native path and present foundation | Missing contract, not an alias |
| --- | --- | --- |
| Bridge Surface | Stable two-edge G0 ruled bridge | Separated/intersecting sheet walls, width/tension, G2/Chamfer, Both/Short/Long/None trims, Sense 1/2 and additional wall pairs |
| Constrained Surface | Retained points, UI/API creation and replacement, bounded point interpolation and angular relaxation | Admissible height-graph projection; native admission rejects unproven geometry |
| Extrude | Profile/curve extrusion; explicit vectors also admit spatial curves | Face/edge operands, angle/wall thickness, Direct/Individual directions, Boolean targets and Keep Tools |
| Loft | Ordered profile/curve sections, mixed single-loop Sheet input, exact guide connectors and discrete spatial contacts, source-sample seams, shared ruled/smooth connectors | General coincident/tangent guide contacts, whole-surface embedding admission and boundary G1/G2 controls |
| Patch | Exact planar hole or admissible nonplanar Coons opening | General N-sided constrained fill, guides and G1/G2 |
| Pipe | Sweep is a reusable native dependency, not a Pipe implementation | Curve/edge paths, circle/polygon/custom sections, diameter/thickness/rotation, end scale, start/end limits, Boolean targets and retained source references |
| PolySplines | Native inline-mesh reconstruction exists | Authored-Mesh conversion/provenance UI; arbitrary mesh and global G2 claims are unsupported |
| Revolve | Profile and certified spatial-curve revolution, explicit Sheet/Solid output | Thickness, curve-to-solid admission, two-point and Normal/Binormal/Tangent axis controls, Boolean targets and Keep Tools |
| Square | Native inline four-boundary Coons builder exists | Referenced boundary authoring, UV degree/span and derivative constraints |
| Sweep | Curve/profile section and independent path, explicit sheet result | Face operands, remaining path-normal/twist/scale combinations, ordered multiple guides with Point/Chord/Curve behavior, Round corners and Simplify; retained options require actual geometry |
| XNURBS | No authoring entry or substitute Fill/Bridge dispatch | General constrained N-sided solver, G1/G2, guides, UV flow and quality guarantees |

Specification references: [Bridge Surface](https://doc.plasticity.xyz/solid/bridge-surface),
[Extrude](https://doc.plasticity.xyz/solid/extrude),
[Revolve](https://doc.plasticity.xyz/solid/revolve),
[Sweep](https://doc.plasticity.xyz/solid/sweep) and
[Pipe](https://doc.plasticity.xyz/solid/pipe), checked on 2026-09-25.
The existing single-section or two-edge UI is not the full input contract.
Sweep guide selection order is retained; Point keeps initial contacts while
rotating/scaling, Chord rotates without scaling, and Curve permits one contact
to slide along the section while retaining the other. A control is complete only
when its geometric behavior, source representation and editing route agree.
The reference manual describes Pipe as an approximate visual tool. Rupa still
requires an explicit approximation allowance and independently verified bounds,
as defined by the system master. No dimensional-accuracy claim follows from the
Pipe name.

Extrude extent and draft interpretation is resolved by the manual together with
Scott Benson's firsthand [Plasticity 2024.2.4 walkthrough](https://www.behance.net/gallery/212202791/Plasticity-from-Scratch-04-3D-Basic-Concepts)
(section Extrude, November 2024). The two distance controls are signed axial
endpoint positions: opposite signs straddle the source section; equal signs
place both ends on the same side. A single draft angle preserves the same wall
slope through both directions, so the form tapers continuously through the
source section. It does not independently flare away from that section on both
sides. This resolves the previously raised user choice; no user decision is
pending. The walkthrough establishes this behavior for its stated version,
not an independent runtime verification of the latest Plasticity release.

Extrude now retains a signed `startDistance` and signed end `distance`. Creation
and history fields expose both endpoints; symmetric mode exposes total distance.
Both UI and semantic API feed CADIR's range validation, and Core measurement,
face offset and dimension/viewport resizing use the same signed interval.
Acceptance distinguishes a continuous drafted wall across the source from two
mirrored tapers. Signed endpoint acceptance covers straddling, same-side,
reverse-only and zero-span endpoints, persistence and source reediting; it does
not establish draft or wall-thickness completion.

This inventory is a scope boundary, not a claim of feature parity. Geometry
algorithms remain owned by Swift-CAD; source edits remain owned by Core and
publication by ProjectWorkspace. Verification owns sheet/solid BRep topology,
parameter effects, declared output/metadata agreement, source preservation,
Undo/Redo and JSON round-trip. UI tests cover family switching, operand selection
and unsupported routes.

Selected-edge Fillet, Chamfer and G2 Blend use the
[Core topology editing](../../RupaCore/TopologyEditing/DESIGN.md) contract,
not extrusion-profile corner rewriting. They require one generated CAD edge
and an amount above modeling tolerance. The kernel's unsupported geometry is
reported by Preview without publication. Subdivision counts are display
quality, so these forms do not expose them as shape parameters. Existing
profile-corner manipulation remains a distinct source-editing operation.

Sheet Offset and Extend Trim use the same source transaction and occurrence
placement contract. Offset accepts signed physical length; Extend Trim accepts
ordered U/V parameter bounds, not physical lengths or unsupported extrapolation.
The kernel verifies the selected face belongs to a single-face sheet. Existing
control-point and boundary-continuity editors remain the editing authority for
their source surfaces. A Plane Surface draft creates an exact bilinear patch
through the existing Core creation command, supplying an editable starting sheet.
Patch and Boundary Bridge submit distinct Core operations; operand count never
selects a different surface algorithm. The boundary affordance opens this same
Surface Creation panel with Boundary Bridge selected; its operation picker also
offers Patch explicitly. The obsolete XNURBS draft has been removed. Its future solver
must own G1/G2, boundary flow, guides, quality and precision before admission.
Preview/Apply/Cancel retain the ordinary Workspace path without a global mode.

Shell uses the same topology-edit and Workspace lifecycle: one selected generated
solid face is the opening and the entered source-coordinate length is thickness.
The panel states the native orthogonal-hexahedron limitation; actual Preview
checks feasibility. It creates no separate geometry or mutation owner.

Sweep exposes an explicit rotation angle and positional approximation allowance.
Double-helical Sweep records angles zero, the entered angle, and zero at path
fractions zero, one-half, and one. This is one source-preserving solid, not two
overlapping bodies. Its midpoint is an intentional angular-rate reversal.
The allowance is independent of display quality and manufacturing tolerance;
unsupported paths and uncertifiable allowances remain visible Preview failures.

- Primitive entries in the palette and Model menu activate the shared Solid
  canvas tool with a MainView-owned `WorkspaceSolidShape`. Click places a default
  primitive; drag sets its rectangle or radius. Sphere uses the construction
  plane's world center; Cylinder extrudes its local circle along the plane normal
  using the existing workspace depth. Circle footprint previews use the same
  radius defaults and explicit input as planning. Box retains its rectangle and
  profile-extrusion routes. Selection never publishes source; click/release uses
  the existing snapshot-bound Workspace transaction.
- Extrude, Revolve, Loft, Fillet and Chamfer are exposed in the palette
  through the existing draft entry point (Boolean and Cut are viewport dialogs,
  `WorkspaceBodyOperation`, not drafts); Sweep retains its canvas route. One
  button renderer owns metrics, colors, selection, accessibility and hover hints.
  Draft forms explain Preview-before-Apply and retain typed operand validation.
  Extrude and Revolve resolve whole-object sections through Core's shared section admission;
  explicit curve selections retain curve intent. Curve sections require Sheet
  output. Revolve's axis and angle are retained by the same source transaction
  used for closed-profile creation. Surface Creation exposes this Sheet operation.

- The parent [canvas tool route](../DESIGN.md#canvas-side-tool-routing) launches
  Surface Creation as the operation family defined above. It retains the
  current ordered selection and the existing preview, Apply, typed validation
  and Cancel lifecycle. A Circle Sketch is a sketch result, not a surface.
- Box, Cylinder, Sphere, Extrude, Revolve, Sweep, Loft, Fillet and Chamfer use existing
  Core commands. Source IDs are allocated by Core, never by this UI component.
- Length text accepts explicit units and otherwise uses the displayed unit;
  angle fields use degrees. All numeric inputs must be finite; a zero revolve
  angle is rejected. A length that gives a new feature its extent, such as a
  size, a radius or an extrude distance, must exceed the document's own
  distance tolerance, because Core refuses one at or below it, and the refusal
  names that threshold as a readable length. Native edge-treatment amounts
  must also exceed that tolerance, matching the kernel. Core's remaining
  geometric requirements, such as whether a sketch
  yields a closed profile or whether an edge treatment holds together, stay
  typed failures from the actual preview rather than preconditions restated
  here.
- A new draft opens at the workspace scale's default feature size, which is
  the size the canvas solid tool places, so the panel and the canvas agree on
  what one default solid is at the current scale. The workspace's interaction
  step is the smallest increment the workspace moves by and is not a size: at
  a fine scale it equals the document's distance tolerance, and a solid whose
  side is the tolerance is degenerate. Fillet and chamfer amounts are
  increments applied to an existing edge and keep the step.
  [RupaCore](../../RupaCore/DESIGN.md) owns both defaults; this component only
  chooses which one a kind opens at.
- Extrude, Revolve and Loft use Core's shared section classification. Explicit
  curve selections retain curve intent; whole source selections resolve closed
  profiles or exact curves. Curve input requires Sheet output. Native geometric
  limitations are reported by preview and do not authorize a different shape.
- Extrude direction is one choice: source normal, symmetric source normal, or
  explicit vector. The form shows vector components only for the vector choice;
  it never asks a spatial curve to fabricate a plane normal. UI and semantic API
  use the same native direction value and exact construction.
- The form shows ordered operands and their roles. Loft section order can be
  changed explicitly. Selection replacement
  is explicit. Authored Mesh cannot masquerade as a CAD feature.
- Feature-only operations other than native topology edits reject transformed occurrences, including transformed
  ancestors, instead of ignoring their world placement. Topology edits retain
  the occurrence placement and interpret the amount in source coordinates. Kernel limitations
  remain typed failures from actual preview/evaluation, not successful fallbacks.
- Editing a draft invalidates the parent's previous preview. Apply is enabled
  only for a completed matching preview and while no operation is running.
  Apply and Preview are disabled during work; Cancel remains available.
- Preview is offered only while the draft names a command. The panel plans the
  draft it is showing against the document it is showing it for, and when that
  plan refuses it disables Preview and displays the reason the plan gave, so a
  press whose only outcome is a refusal is never offered. `command(in:)` stays
  the one place that decides what a draft means; the panel reads its refusal
  rather than restating the preconditions. The reason is a function of the
  draft and the document read while the view is built, not an event, so it is
  displayed and not recorded; the workspace's
  [failure surfacing](../DESIGN.md#failure-surfacing) rule owns that split.
  Planning walks each operand's ancestors by scanning the scene node table, so
  the panel pays that walk once for every evaluation of its body.
- The Definitions inspector exposes existing named parameter expressions and
  their dependency/dependent summaries through the existing parameter editor.
  Topology-edit amounts retain named length expressions through the existing
  parameter parser and Core commands. Planning resolves the expression only
  to check its current finite value and tolerance; it does not replace the
  source expression with that value. Definitions edits then use existing
  reevaluation, atomic failure and Undo. Other creation fields remain literal
  inputs until their source contracts are connected explicitly.

## State, Ownership, and Lifecycle

SwiftUI owns the value draft for one operation. Cancel, document replacement or
successful commit releases it. Published snapshot coordinates are retained by
the parent operation flow, not inferred from draft contents.

## Verification and Change Impact

`Tests/RupaUIPackageTests/ModelingOperationDraftTests.swift` verifies exact
parameter forwarding, operand order, invalid inputs and transformed/non-CAD
selection refusal. For every workspace scale preset it also evaluates the
command a newly opened primitive draft names, so a default the kernel would
refuse is a test failure rather than a failure record at run time. It holds
the two thresholds apart by driving both: a size at the document's distance
tolerance names no command, and an edge amount at that same tolerance is also
refused. It also holds that an operand
producing no profile is refused before the press, reading the refusal text so
another precondition cannot pass the check for it. Parent
integration tests own preview cancellation, stale completion and
exactly-once Apply. Signed App tests own actual controls and
geometry display. The layout reuses native SwiftUI controls and existing
Workspace spacing/semantic colors; no separate web-style design system is added.
Surface-fill UI tests verify Preview/Apply/Cancel, complete labels and absence of
any persistent tool-mode mutation. The signed App must show the hover affordance
and generated editable sheet while preserving the source object and supporting
Undo/save/reopen.
Validation includes keyboard labels, disabled/busy/error states, light/dark
appearance and increased contrast at the App boundary.

### Constrained Surface interaction

The modeling draft owns ordered point constraints and numerical option text.
Canvas clicks append world-space positions before ordinary selection routing.
Coordinate entry and point replacement use the same draft; Control-Z removes
the last point. Preview and Apply retain the existing revision-matched atomic
command contract. History opens the retained points and options, with the feature
ID targeting source replacement. Cancel discards only the transient draft.
The native source/evaluator contract is documented in
[Constrained Surface](../../../../swift-CAD/Sources/CADModeling/ConstrainedSurface/DESIGN.md).
