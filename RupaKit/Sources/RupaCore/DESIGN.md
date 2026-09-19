# RupaCore Source Authority Design

## Purpose and Scope

This module owns Product/CAD/Authored-Mesh source mutation, persistent source
identity allocation, and the Core-side application of a bounded Mesh edit
plan. It is a child of the
[RupaKit package design](../../DESIGN.md) and the
[system design](../../../DESIGN.md).

Dependencies used by this boundary are `RupaCoreTypes`, `RupaGeometry`,
`RupaProjectModel`, and Swift-CAD. Users include `RupaProject`, `RupaKit`, and
existing application/domain adapters through the public Core contracts.

Parent: [RupaKit package design](../../DESIGN.md). Children: none.

## Responsibilities and Boundaries

### Spatial path editing

[SpatialPathEditing](SpatialPathEditing/DESIGN.md) owns explicit planar-to-spatial
conversion and transactional edits of spatial source knots. It uses Swift-CAD's
source operations; no viewport coordinates are persisted as source geometry.

### Box Corner source

`Corner` is an exact all-edge box fillet. Core retains the visible feature ID
and scene placement, moving its original extrusion into an intermediate input
and using the visible feature for the fillet. Setting zero restores that extrusion
and removes only its unshared intermediate input. Dimension editing resolves
through this all-edge wrapper; other fillets are not editable box primitives.
The radius must be zero or greater than the modeling tolerance and strictly
below half the shortest dimension. Rejected edits publish no source or property
change. `Corner Sides` is a positive display subdivision count, not exact geometry.
Verification covers source bounds, radius-zero restoration, source dimensions,
property failure atomicity, persistence, and command history.
Core resolves display tessellation options from the current exact radius and
product subdivision count. Both modeling evaluation and the universal project
provider consume that result, so a staged evaluation can seed the published
artifact without changing its fidelity identity. Invalid quality throws before
evaluation; the existing scheduler reports it as failure.

The existing `ObjectDimensionSourceResolver` is also available within this
package for Inspector projection from a published, validated document. It is
the same resolver used by `setObjectDimension`; UI must not substitute placed
render bounds or copied object-property defaults for source dimensions. Its
read-only query throws for unsupported or unresolved source. This widens no
external API and changes no persistence or mutation authority.

`RupaCore` owns:

- server allocation of every persistent CAD, sketch-entity, Product, Scene,
  Component, Instance, and Pattern identity created by a Core command;
- high-level CAD commands that validate and atomically append exact source
  features plus their Product presentation metadata;
- materializing ID-free ordered sketch-construction values into a validated
  `Sketch` without accepting caller-minted `SketchEntityID` values;
- analytic-sphere source creation through swift-CAD's existing
  `SpherePrimitive` evaluation path;
- `DesignDocument` Product metadata and retained representation references;
- retained Authored Mesh assets and their provenance;
- source-authority target validation using only `sourceID` and expected content
  identity;
- applying one complete Mesh plan through the injected Geometry executor;
- consuming Geometry's already-validated execution without duplicating or
  replaying operation/output rules;
- replacing only the matching asset after full success and preserving all
  Product/CAD/selection/provenance values;
- semantic document validation and Core command results;
- immutable, deterministic Product scene-graph projections that expose
  identity, hierarchy, source linkage, visibility, lock state, and transforms
  without evaluating or copying CAD/Mesh geometry.
- effective scene-node visibility resolved from the Product root hierarchy;
  a hidden ancestor suppresses every descendant without deleting its source.
- object display-name mutation at the owning Product identity: ordinary scene
  nodes own their names, while a component instance owns the name mirrored by
  every scene node that references it;
- atomic publication of an imported Authored Mesh through a geometry-source
  command. The command receives an already validated `MeshSource` and its
  sanitized content provenance; Core allocates the Product source,
  representation, and Scene identities and validates the complete staged
  document. Core does not read files or parse exchange formats.

It does not own semantic CAD operation descriptors, Agent schemas, Mesh
algorithms, plan execution internals, project package I/O, project revision
publication, view projection, or Agent/CLI/MCP transport.
`SceneNodeID` and `GeometryRepresentationID` remain navigation/reference values
outside the Mesh source target; they are not required inverse references and do
not establish Mesh source authority.

```mermaid
flowchart LR
    Command["Source-authority Mesh plan command"] --> Validate["Core document + sourceID/content identity validation"]
    Validate --> Execute["Injected RupaGeometry plan executor"]
    Execute --> Replace["Replace matching Authored Mesh asset"]
    Replace --> Document["Validate staged DesignDocument"]
    Document --> Result["Immutable Core result + Mesh receipt"]
```

### Current baseline and T09 delta

The current Core path in
[AuthoredMeshEditCommand.swift](AuthoredMeshEditCommand.swift),
[AuthoredMeshEditTarget.swift](AuthoredMeshEditTarget.swift), and
[DefaultGeometrySourceCommandApplier.swift](DefaultGeometrySourceCommandApplier.swift)
accepts one operation and carries scene/representation IDs in its target. T09-B
replaces that public operation/target shape with one source-authority target and
one complete plan. The existing Core validation and transaction/history boundary
remain the integration point.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [package design](../../DESIGN.md) | parent package | Package authority direction | Places Core between Geometry and Project. | Do not publish from Core directly. |
| [system design](../../../DESIGN.md) | system parent | Source identity, shared references, one-plan flow | Defines the cross-layer behavior. | Local document validation remains Core-owned. |
| [RupaGeometry design](../RupaGeometry/DESIGN.md) | depends on | Plan/executor/receipt and buffer contract | Supplies immutable result and copy telemetry. | Core must not reimplement Geometry algorithms. |
| [Swift-CAD package design](../../../swift-CAD/DESIGN.md) | depends on | Exact evaluated B-rep topology, stable subshape references, and derived Mesh | Supplies the immutable evaluation and exact solid geometry consumed by Core measurement. | Core must not repair signatures, substitute Mesh volume, or create a sphere-specific measurement path. |
| [RupaCADDomain design](../RupaCADDomain/DESIGN.md) | used by | High-level source commands and server-owned identity results | CADDomain lowers universal semantic operations to Core commands. | CADDomain may not construct persistent IDs or raw source graphs. |
| [CAD/Mesh responsibility](../../../Rupa/CAD_MESH_RESPONSIBILITY_CONTRACT.md) | depends on | Authored Mesh authority, CAD coexistence, provenance | Defines representation meaning and CAD/Mesh independence. | Do not alter CAD or selection when editing Mesh. |
| [State and project contract](../../../Rupa/STATE_AND_PROJECT_CONTRACT.md) | coordinates with | Source history and transaction staging | Project owns publication and revision. | Core results are staged values until Project commits. |
| [RupaCore tests](../../Tests/RupaCoreTests) | verification owner | Source-authority behavioral tests | Owns current/stale/shared-reference proof. | Type/shape tests alone are insufficient. |

## Architecture

CAD creation and Authored Mesh editing share the same source-authority boundary
but not the same mutation semantics:

```mermaid
flowchart LR
    Semantic["validated CAD semantic step"] --> Command["high-level EditorCommand"]
    Command --> Core["RupaCore validation + ID allocation"]
    Core --> CAD["exact swift-CAD source feature"]
    Core --> Product["Product object + Scene presentation"]
    CAD --> Delta["complete generated source identity delta"]
    Product --> Delta
```

```mermaid
flowchart TD
    Target["AuthoredMeshSourceTarget\nsourceID + expected content identity"] --> Lookup["Retained asset lookup"]
    Lookup --> AssetCheck["Authored Mesh domain + asset key/sourceID"]
    AssetCheck --> Plan["AuthoredMeshEditPlan"]
    Plan --> Executor["RupaGeometry executor"]
    Executor --> Execution["Validated Mesh execution + receipt"]
    Execution --> Asset["Asset replacement preserving provenance"]
    Asset --> Validate["Full DesignDocument validation"]
    Validate --> Application["Staged Core application"]
```

```mermaid
flowchart LR
    Exchange["Format adapter\nvalidated MeshSource + fingerprint"] --> Import["ImportAuthoredMeshCommand"]
    Import --> Core["Core identity allocation + document validation"]
    Core --> Project["ProjectSourceTransaction"]
    Project --> Publication["Project-owned atomic publication"]
```

An Authored Mesh asset may be referenced by multiple Product Objects or
representations. Source editing operates on that shared asset authority, so all
retained references observe the same replacement. Core never silently makes a
unique copy to satisfy a single scene selection.

## Contracts and Invariants

### Product object naming contract

1. `renameSceneNode` changes only the normalized, nonempty name of an ordinary
   `SceneNode`. It preserves the node ID, hierarchy, reference, object,
   transform, visibility, lock, material, geometry, and every CAD feature name.
2. A scene node that represents a component instance is renamed through
   `renameComponentInstance`. The component instance is the naming authority;
   Core updates its name and every scene node whose reference or object
   descriptor names that instance in one validated mutation. Existing
   component-instance uniqueness remains in force.
3. A scene node with a retained `constructionPlaneID` is renamed through the
   existing `renameConstructionPlane` contract, which updates the construction
   source and its scene-node mirror together. A generic construction scene node
   without a retained construction-plane source remains an ordinary scene node.
4. A pattern-array root is renamed through the existing
   `updatePatternArray(name:)` contract, which updates the source and group node
   together. A generated pattern output cannot be renamed independently.
   Core returns a typed command failure instead of changing generated output
   metadata that its source will later regenerate.
5. After normalization, renaming an ordinary scene node to its current name is
   a no-op. Renaming a component instance is a no-op only when the authority and
   every reference/object scene-node mirror already carry that normalized name.
   A no-op does not advance generation, evaluate, dirty the document, or create
   undo history. A same-name component-instance request repairs inconsistent
   mirrors as one ordinary mutation rather than hiding the inconsistency.
6. A list of existing visibility or lock commands submitted as one project
   source transaction remains one isolated source-command group: all commands
   are accepted and published with one undo entry, or the staged document and
   history both roll back. Product naming does not introduce another batch or
   publication owner.

```mermaid
flowchart LR
    Intent["Object-name intent"] --> Classify{"Product owner"}
    Classify -->|ordinary node| Node["SceneNode.name"]
    Classify -->|component occurrence| Instance["ComponentInstance.name"]
    Instance --> Mirrors["All referencing SceneNode names"]
    Classify -->|saved construction plane| Plane["Existing ConstructionPlaneSource rename"]
    Classify -->|pattern root| Pattern["Existing PatternArraySource update"]
    Classify -->|generated output| Refuse["Typed refusal"]
    Node --> Validate["Validate staged DesignDocument"]
    Mirrors --> Validate
    Plane --> Validate
    Pattern --> Validate
```

### Product hierarchy move contract

`EditorCommand.moveSceneNodes(ids:parentID:beforeSiblingID:)` is the Core
source command for Product hierarchy changes. The command owns hierarchy
validation and placement math; Outliner and drag/drop callers supply stable
IDs and do not mutate `ProductMetadata` directly.

1. `ids` must be non-empty, unique, and present in the current hierarchy.
   Descendants of another selected ID are collapsed, and the remaining
   top-level subtrees retain their current pre-order scene order. `parentID`
   is either an existing scene node or `nil`, where `nil` means the document
   root list. `beforeSiblingID` is either `nil` (append) or an actual direct
   child of that destination parent (or an actual root ID for a root drop);
   it is never a filtered-row index and cannot belong to a moved subtree.
2. A move is rejected atomically for a missing/empty selection, stale
   generation (enforced by `EditorSession`), duplicate ID, self/descendant
   cycle, invalid anchor, locked selected subtree or destination, empty root
   result, non-finite/non-affine/singular placement matrix, and any source
   authority that cannot preserve its invariants. Pattern roots and generated
   Pattern output subtrees, saved construction-plane nodes, and component
   definition source subtrees are source-owned and cannot be moved. A normal
   Product scene node that references a ComponentInstance is an occurrence
   placement and is not rejected solely for being an instance; generated
   Pattern occurrences remain source-owned through the Pattern resolver.
3. A same-parent reorder changes only the parent child/root ID arrays. Every
   selected node's `localTransform` remains bit-for-bit unchanged. A reparent
   computes each moved root's old world transform before changing hierarchy
   and assigns `newLocal = inverse(destinationWorld) * oldWorld` using the
   row-major, column-vector convention above. Descendant IDs, geometry,
   feature history, names, visibility, lock state, material, and all source
   references remain unchanged.
4. The operation stages one complete `ProductMetadata`, validates it with the
   existing document validator, and publishes it through the existing
   `CADDocumentStore`/`CommandStack` path. A successful move is one source
   mutation and one undo entry. A no-op reorder does not advance generation,
   evaluate, dirty the document, or create history. Failure leaves document,
   generation, evaluation, and history unchanged. The consumed-profile
   `ProductMetadata.nestSceneNode` helper is not a generic move implementation.

```mermaid
flowchart LR
    Intent["stable IDs + destination"] --> Classify["Core selection/order + source ownership"]
    Classify --> Placement["same-parent reorder or affine world-preserving reparent"]
    Placement --> Validate["stage and validate ProductMetadata"]
    Validate -->|success| Commit["one Core mutation + one undo"]
    Validate -->|failure| Refuse["typed refusal; no publication"]
```

The focused Core tests own top-level selection collapse, stable source-order
multi-move, root-list moves, same-parent bit preservation, world-preserving
reparenting, cycle/anchor/lock/source-owned refusals, atomic rollback,
no-op behavior, stale generation, and one-step undo/redo.

### Scene placement matrix convention

Scene and component placement use row-major `Matrix4x4` storage with column
vectors: translation is at indices 3, 7, 11 and world placement is parent times
local. This agrees with `RupaGeometry.GeometryTransform3D`, the Product bridge
and CAD semantic lowering. UI, pattern generation, analysis and legacy CAD
overlays must use this same convention. The old column-major UI convention is
removed by explicit product decision; no decoder guessing or migration fallback
is provided. Existing user files are not deleted automatically.

The placement inspector accepts finite, non-singular affine matrices, including
shear produced by world-axis scaling after rotation. Its canonical decomposition
is `T * Rz * Ry * Rx * H * S`, where H is upper triangular with unit diagonal
and dimensionless XY, XZ and YZ shear. QR decomposition fixes Y/Z scales positive
and retains reflection in signed X scale. Numeric TRS edits retain H; no
orthogonalization may discard deformation. Perspective and singular matrices
remain typed refusals. Near gimbal lock an equivalent Euler form fixes Z to zero.
Round-trip tests cover world-axis scale after rotation, reflection, shear,
numeric edits and explicit failure. Existing shear-free placements keep their
TRS interpretation and serialized matrix format unchanged.

`ModelingOperationDraftTests`, `WorkspaceTransformMatrixTests` and viewport
transform tests own UI intent and geometry agreement; signed-App verification
must confirm CAD overlays and Mesh rendering coincide after XYZ edits.

Product object-name tests own ordinary-node preservation, component-instance
mirror consistency and uniqueness, pattern-root reuse, generated-output
refusal, saved-construction-plane owner routing, true no-op behavior, mirror
repair, stale transaction refusal, grouped rollback, and undo/redo. They do not
infer successful Outliner interaction from command construction alone.

For CAD command results, Core guarantees the staged-source phase of the
[package identity-phase contract](../../DESIGN.md#cad-identity-phases). One
immutable result delta is derived from the accepted staged document and may
contain generated Feature, source body-output role, Scene Node, Component
Definition, Component Instance, and Pattern Source identities. It never
contains evaluated topology `BodyID`; evaluation and publication are not Core
command-result responsibilities. An identity absent from the accepted staged
source, a duplicate or wrong-kind identity, and an identity reported by a
failed, rolled-back, or no-op mutation are invalid.

For package-internal prepared execution, `EditorSession` exposes only the
read-only fact that its existing `CommandStack` currently owns an active source
command group. The observation cannot enter, leave, or retain the group and
does not expose the stack. It allows `RupaAutomation` to reject execution on an
ordinary session before mutation; source rollback, deferred evaluation, and the
single history entry remain owned by `withSourceCommandGroup`.

### CAD creation contract

1. `createAnalyticSphere(name:center:radius:)` is a high-level source command.
   Core validates a non-empty name, finite center, and a radius greater than the
   document tolerance, allocates the `FeatureID` and `SceneNodeID`, appends one
   `PrimitiveFeature(.sphere)` with a `.body` output, and creates one solid
   Product object with `ObjectTypeID.sphere` and a radius property. Center is
   source placement, not a duplicated Product transform. The radius property is
   read-only metadata until a dedicated source-edit command owns radius changes;
   every Product validation requires the object to reference an analytic sphere
   primitive and requires its radius to equal the resolved CAD source radius, so
   editing Product metadata alone cannot diverge from the CAD source.
2. Sphere creation is atomic across CAD and Product state. Validation,
   append, Product synchronization, or evaluation failure leaves both values
   unchanged. A successful command delta contains exactly one generated
   Feature, one `.body` source-output identity, and one Scene node; it contains
   no evaluated `BodyID`.
3. The exact evaluator remains swift-CAD's existing
   `SpherePrimitive -> PrimitiveFeatureEvaluator ->
   PrimitiveBRepRequestBuilder.sphere` path. For a valid isolated sphere it
   produces eight analytic spherical faces, twelve exact edges, six vertices,
   and analytic volume; Core must not tessellate, approximate, or substitute an
   Authored Mesh.
4. `createSemanticSketch(name:plan:geometryRole:)` accepts a
   `SketchCreationPlan` containing a plane, ordered ID-free
   `SketchCreationEntity` values, and `SketchCreationConstraint` values that
   refer to entities only by validated zero-based local indices. Core rejects
   empty/duplicate/out-of-range/self-incompatible references before source
   append, allocates one `SketchEntityID` per entity in input order, resolves
   all constraint references, then delegates to the ordinary complete-Sketch
   validation and append path.
5. The initial ID-free entity contract covers line and analytic circle; the
   relation contract covers coincident endpoint references, parallel,
   perpendicular, horizontal, vertical, equal length, concentric, and equal
   radius. Relation/entity-kind compatibility is validated in Core. These are
   universal sketch values, not benchmark-case commands.
6. A semantic sketch command reports the generated sketch Feature and Scene
   identities through the ordinary complete delta. Internal
   `SketchEntityID` values are neither request values nor CADAPI-A local
   outputs. A later program step refers to the generated sketch Feature, not
   to a fabricated entity identity.
7. Adding either command requires updating every exhaustive `EditorCommand`
   classification. Prepared Automation admits both as source commands and
   continues to reject raw `appendFeatureGraph` and caller-built `Sketch` as
   semantic Agent inputs.

### Authored Mesh edit contract

1. The Mesh edit target contains only `GeometrySourceID` and expected
   `ContentIdentity`. Scene-node and representation IDs are not part of source
   authority.
2. Public application validates the document once before dispatch. The retained
   `AuthoredMeshAsset` invariant guarantees that construction and decoding
   already validated its source and computed or verified its cached content
   identity. After document validation, Core performs one O(1) authority check:
   dictionary key, asset/source ID, identity domain, and cached content identity
   against the target. It does not revalidate or rehash the existing source. A
   CAD-derived snapshot, external observation, or arbitrary Mesh payload cannot
   be promoted by identity imitation.
3. The target may name a retained-but-unselected asset; Core does not require an
   inverse Object or representation reference to apply the edit.
4. The Core command contains one complete plan. `MeshEditPlanExecuting` returns
   an already-validated `MeshEditPlanExecution`, whose raw initializer is not
   public. Core trusts that type invariant and does not rescan the original or
   result source, validate the execution again, or duplicate output-role,
   alias, ID-lifecycle, allocation, or topology rules. It replaces the asset
   under the same source ID only after execution succeeds and the complete
   staged `DesignDocument` validates. That aggregate document validation is a
   separate Core authority boundary, not authorization for a second execution
   semantic validator.
5. Shared source references remain shared. Core does not clone the source or
   synchronize CAD, purpose selection, or representation metadata as a side
   effect.
6. CAD bytes, Product metadata, representation IDs, modeling/presentation
   selection, and Authored Mesh provenance are byte-for-byte/semantically
   invariant for a Mesh-only edit, except for the edited asset payload and its
   content identity.
7. A no-op plan preserves the asset content identity and produces a no-op result.
8. Plan receipt and copy telemetry survive the Core result boundary for Project
   staging and verification.
9. Core does not make a derived evaluation snapshot an Authored Mesh source;
   explicit Make Editable remains a separate command.
10. A scene-graph result reports Product scene nodes in deterministic ID order
    and preserves root ordering. It does not evaluate CAD/Mesh geometry, mutate
    source, or treat CAD-local body bounds as placed geometry.
11. Effective visibility is derived only from Product root reachability and each
    node's `isVisible` value. Hidden nodes and descendants remain retained source
    and navigation identities; presentation consumers omit them without deleting
    CAD features, representations, or Authored Mesh assets.

### Imported Authored Mesh contract

1. File access and format parsing remain outside Core. The import adapter must
   provide a validated `MeshSource`, an `AuthoredMeshProvenance.imported`
   identity, and a display name; the identity contains only a qualified format
   domain and content fingerprint, never an absolute path.
2. `ImportAuthoredMeshCommand` allocates one source ID, representation ID, and
   scene-node ID inside the staged Core document. It creates one body/mesh
   Product object whose modeling and presentation selections point at the same
   retained Authored Mesh representation.
3. The command rejects duplicate identities, missing root hierarchy, invalid
   imported provenance, or a document that fails complete validation. It never
   mutates the caller's document on failure and never publishes directly.
4. `ProjectSourceTransaction` runs the command through the existing geometry
   command applier. Project remains the owner of revision checks, evaluation,
   undo/redo, package encoding, and publication; a failed or cancelled import
   therefore produces no partial source or Product state.

### Feature history command contract

Feature history mutations use the existing `EditorCommand` and
`EditorSession` source-transaction boundary. Core owns candidate document
validation; `ProjectController` remains the only publication owner.

| Command | Core guarantee | Failure and history behavior |
|---|---|---|
| `setFeatureSuppression` | Changes only an existing feature and validates the complete staged `DesignDocument`; an active feature may not depend on a suppressed source. | Missing IDs and dependency-invalid suppression return typed failure with no document, generation, or history change. A same-value request is a no-op. |
| `reorderFeatureGraph(featureIDs:)` | Accepts exactly one permutation of the current feature IDs. Core validates the candidate graph's dependency direction, inputs, operation contracts, Product references, and evaluation before assigning it. | Duplicate, missing, extra, or dependency-unsafe IDs return typed `invalidGraph` failure with no partial order or history entry. A same-order request is a no-op. |
| `upsertParameter`, `renameParameter`, `deleteParameter` | Applies the existing parameter validation and pattern regeneration path atomically. | Unknown, duplicate, self-referencing, or still-referenced parameters return typed failure and restore the prior source. |

Every successful mutating history command is staged in an isolated
`EditorSession`, produces one evaluated source mutation and one command-stack
entry, and is published only by `RupaProject`. Core never publishes a candidate
or turns a failed candidate into the previous document as a success result.

### Snap topology demand contract

`SnapResolver` owns the decision to request a topology summary while resolving
object candidates. It requests the existing `TopologySnapshotService.snapshot` with
`metricPolicy: .omit` exactly when:

```text
measurementsRequireTopology(in: document)
|| (searchRadiusMeters > 0
    && document.cadDocument.hasActiveRenderableTopologyFeatures)
```

The positive-radius branch is limited to active renderable CAD topology. An
authored-mesh-only or sketch-only document therefore continues through grid,
sketch, region, and other non-topology candidates without entering whole
document topology validation. While resolving object candidates, a measurement anchor of kind
`topologyReference` or `topologyEdgeParameter` forces the existing topology
service, even when the search radius is zero or the document has no active
renderable CAD topology. `TopologySnapshotService` remains the validation and
CAD/measurement failure authority; SnapResolver adds no cache, alternate
topology path, or failure conversion of its own.

Each `resolve` runs object candidate resolution on the caller's thread, and on
a document with active renderable CAD topology the demand above reaches one
exact kernel evaluation of the whole document. One pointer event can call it
more than once: a canvas drag resolves its start and then its end. `resolve`
therefore accepts the caller's published `DocumentEvaluationContext` and
`DocumentGeneration` and forwards both to that one `snapshot` call, exactly as
`MeasurementService` and `MeshSummaryService` already forward them. The context
stays the caller's: SnapResolver neither stores nor updates it, and
`TopologySnapshotService` alone decides whether it matches. A caller that
supplies no context, or one whose generation, modeling settings, or source
identity no longer describe the document passed beside it, is answered by the
same exact evaluation as before, so the reuse cannot return topology from a
document the caller did not ask about. `SnapResolver.init` takes the
`TopologySnapshotService` it calls, so a test can hand it a service whose exact
evaluator refuses to run and read the difference between a matching context and
no context as success against failure.

### Evaluated primitive measurement contract

Every solid `PrimitiveDefinition` uses the same output-driven
`measureEvaluatedBodySolids` path as other evaluated body operations. The
resolved evaluated body is the exact B-rep volume authority; its evaluated Mesh
is used only for presentation surface area and bounds. A primitive kind is not a
reason to skip output measurement, and a missing evaluated body, Mesh, or exact
volume remains a diagnostic rather than a fabricated success.

```mermaid
flowchart LR
    Primitive["Primitive source feature"] --> Evaluation["One immutable evaluated document"]
    Evaluation --> Body["Generated solid body output"]
    Body --> Volume["Exact B-rep volume"]
    Body --> Mesh["Derived Mesh surface area/bounds"]
    Volume --> Result["MeasurementResult.Solid"]
    Mesh --> Result
```

This contract preserves source feature identity, selection filtering, and
supersession behavior. It does not add a second measurement model or infer
solid geometry from source parameters.

### Body display face-run contract

`BodyDisplaySnapshot.Topology.meshFaceRuns` records which CAD face generated
each contiguous run of the snapshot's drawn triangles. It is the identity the
viewport reads when the native frame reports the triangle it hit, so the runs
are derived once with the snapshot and are never rebuilt per camera move or per
click, and no side table keyed by mesh identity exists to fall out of step with
the snapshot they describe.

```mermaid
flowchart LR
    Kernel["swift-CAD tessellation"] -->|"Mesh.faceRuns"| Evaluated["Evaluated document mesh"]
    Evaluated --> Service["BodyDisplaySnapshotService"]
    Service -->|"Topology.meshFaceRuns"| Snapshot["BodyDisplaySnapshot"]
```

The runs are independent of `Topology.faces`. A `Face` carries the projected
outer loop a CPU polygon test needs and is absent for a face without one, while
a run needs no polygon and describes exactly the triangles the frame draws. A
face that evaluation gave no stable sub-shape identity records no run; the
omission is truthful absence, and a hit on such a triangle is reported as a miss
rather than answered with a neighbouring face. A run always carries the prepared
`SelectionComponentID`: Core never substitutes a mesh identifier for a CAD
identifier.

### Executor substitution boundary

The public `DefaultGeometrySourceCommandApplier` initializer selects
`DefaultMeshEditPlanExecutor` and does not accept an external executor. A
package-scoped initializer accepts the package-scoped `MeshEditPlanExecuting`
seam for same-package composition and tests. T09 does not promise external
executor substitutability; Agent, CLI, MCP, and future provider transports use
the Core command boundary rather than injecting an executor.

Core tests may inject a package test executor that delegates to the default
executor or throws a typed failure. They do not construct malformed execution
values or test Core revalidation, because invalid candidates cannot cross the
production Geometry boundary.

## Runtime Flows

```mermaid
sequenceDiagram
    participant A as Prepared Automation
    participant S as Staged EditorSession
    participant D as DesignDocument
    participant K as swift-CAD evaluator
    A->>S: high-level sphere or ID-free sketch command
    S->>D: validate and allocate all persistent identities
    D->>D: append exact CAD + Product presentation atomically
    D->>K: evaluate exact source
    K-->>S: exact evaluation or typed failure
    S-->>A: complete generated source delta
```

```mermaid
sequenceDiagram
    participant P as Project staging
    participant A as Core applier
    participant E as Mesh executor
    participant D as DesignDocument

    P->>A: source-authority plan command
    A->>D: validate document once and locate sourceID
    A->>A: O(1) key/source/cached identity check
    A->>E: execute plan against retained MeshSource
    E-->>A: validated execution
    A->>D: replace asset and validate complete staged document
    D-->>P: staged document + Core result
```

If execution or validation fails, the original document value remains unchanged.
The project layer decides whether and when the staged value is published.

## State, Ownership, and Lifecycle

- `DesignDocument` owns the retained asset dictionary and Product references.
- `DesignDocument` owns every persistent identity materialized from an ID-free
  sketch plan and the Feature/Product state created for an analytic sphere.
- `RupaGeometry` owns the temporary mutable buffer during plan execution.
- `AuthoredMeshAsset` owns published Mesh source identity, payload, and
  provenance.
- Core application results are immutable staged values and do not publish by
  themselves.
- Undo/redo and transaction revision are recorded by `EditorSession`/
  `ProjectController` around the Core application, not inside the Geometry
  executor.

## Failure, Concurrency, and Constraints

Core rejects invalid or degenerate CAD creation values, invalid ID-free sketch
indices/relations, source-domain mismatch, an asset dictionary key/source-ID mismatch,
missing asset, stale content identity, executor failure, and post-replacement
document validation failure with typed errors. It never returns the original
asset as a success fallback after a failed edit and it does not fail merely
because no inverse Object/reference is present.

The Core value path is immutable during asynchronous project staging. Any
mutable session access remains inside the existing project/session isolation
boundary. No `await`, package I/O, or external callback occurs during a Geometry
buffer borrow.

## Verification and Change Impact

T09-B owns the following behavioral proof:

| Invariant | Required evidence |
|---|---|
| Authority | Current, stale, missing, domain/key/source-ID, retained-but-unselected, and no-inverse-reference source cases. |
| Plan integration | One complete plan, receipt propagation from a validated execution, one executor invocation with no Core replay, valid create-then-delete lifecycle, no-op identity stability, and mid-plan rollback. |
| Shared source | One edited asset is visible through every retained representation reference; no implicit clone. |
| Independence | CAD/Product/selection/provenance bytes remain unchanged after Mesh edit. |
| History | One command-history entry plus undo/redo behavior. |
| Error handling | Typed failures do not publish a partial document. |
| Product visibility | Root, hidden-parent, visible-sibling, and hidden-descendant cases prove one effective-visibility result without source deletion. |
| Evaluated primitives | Box, cylinder, cone, sphere, and torus all produce evaluated-body solids with exact B-rep volume and Mesh-only area/bounds through one cached evaluation path; unavailable outputs remain diagnostics. |
| Snap topology demand | Positive-radius authored-mesh-only object resolution skips whole-document topology validation and still returns grid/non-topology candidates; topology measurement anchors force the existing validation failure during object resolution; existing CAD snap and measurement cases remain green; a matching caller evaluation context resolves object candidates on a CAD document without consulting the exact evaluator, and the same resolve without that context still consults it. |
| Body display face runs | `Tests/RupaCoreTests/BodyDisplaySnapshotServiceTests.swift` proves an evaluated box snapshot records one run per prepared face, that the runs carry the same prepared identities as `Topology.faces`, and that they partition every drawn triangle contiguously from zero to the snapshot's triangle count. |

CADAPI-C must additionally prove:

| Invariant | Required evidence |
|---|---|
| Exact sphere | Origin and translated valid spheres retain the requested center/radius, `ObjectTypeID.sphere`, one body role, and exact 8/12/6 analytic B-Rep; zero/negative/tolerance-sized radius and nonfinite center fail without source/Product/history change. |
| Identity ownership | Repeating the same ID-free sketch plan creates distinct server-owned entity identities; no Core creation input contains `SketchEntityID`. |
| Constraint materialization | All eight supported relations materialize correctly; missing/out-of-range indices, wrong entity kinds, invalid coincident endpoints, and duplicate/self references fail atomically. |
| Command admission | Every exhaustive Core/Automation command classification handles history and CAD source commands, and raw graph/legacy caller-built Sketch does not become a semantic CAD operation. |

Changes to CAD creation, target identity, asset replacement, provenance, or
Core command decoding require rechecking `RupaAutomation`, `RupaCADDomain`,
`RupaProject` staging, and the system source-authority invariants.
