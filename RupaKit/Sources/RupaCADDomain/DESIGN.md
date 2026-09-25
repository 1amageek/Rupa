# RupaCADDomain Semantic CAD Design

## Purpose and Scope

`RupaCADDomain` owns Rupa's concrete, versioned semantic CAD operation
vocabulary, typed output declarations, and lowerers into the coordinate-free
prepared source-program contract. The same registry serves direct invocation
and declarative programs. This module is a child of the
[RupaKit package design](../../DESIGN.md).

Parent: [RupaKit package design](../../DESIGN.md). Children: none.

## Responsibilities and Boundaries

Solid profile extrusion, profile sheet extrusion and curve sheet extrusion share
`ExtrudeLowerer` and the Core section transaction. Their descriptors declare the
actual source-body output role, so sheet receipts cannot be relabeled as solids.
`cad.surface.extrude` consumes `profile`; `cad.surface.extrudeCurve` consumes
`curve`. Both use the same length and direction contracts as `cad.solid.extrude`.
The optional `start_distance` and required `distance` are finite signed axial
positions in meters; omission starts at zero. Equal endpoints are rejected before
preparation; the native range contract additionally enforces modeling tolerance.
The additive optional field preserves existing version-one invocations.
Semantic execution tests check both sides and same-side reversed endpoints
against the generated BRep, not only command construction.

Revolution uses `RevolveLowerer` and Core's `revolveSection` transaction for
solid profiles, sheet profiles and sheet curves. Inputs specify an axis origin
in meters, a nonzero axis direction and a signed angle in degrees. The accepted
angle is nonzero and at most one turn. Geometric admission remains owned by the
native evaluator; lowering never substitutes a mesh or another operation.

Profile Loft sections optionally accept `profileIndex`, a nonnegative unitless
integer selecting the exact extracted region; omission selects region zero.
Curve sections reject this field. The native resolver rejects indexes outside
the evaluated profile collection; the lowerer never clamps or substitutes one.
Loft sections optionally accept `startSampleIndex`, a nonnegative unitless integer
in the native Int range. It addresses the original source samples before curve
restriction/reversal; omission selects automatic correspondence. Native evaluation
owns source bounds and exact seam admission for both create and replace.
Loft uses one lowerer with solid and sheet result descriptors. `sections` is an
ordered array of objects requiring `kind` (`profile` or `curve`) and
`source` (a typed feature reference), with optional `tangentScale` (finite,
positive, unitless) and `tangentMode` (`automatic` or `zero`).
Curve sections additionally accept `parameterRange`, a two-element
array of finite unitless values in the source curve's native parameterization,
with increasing endpoints. Profile ranges are rejected; source containment is
validated by shared native section resolution. Unknown fields are
rejected. Omitted tension inherits the operation tension; omitted mode is
automatic. These controls set native smooth interpolation derivatives, not
support-surface G1/G2 constraints. Sheet sections may mix profiles and curves;
Curve-only `reversed` is an optional boolean, defaulting to false.
Profile-only `profileDirection` accepts `automatic`, `forward` or `reversed`,
defaulting to automatic. Curve inputs reject this field even when its value is
automatic, keeping the two direction authorities distinct. Both creation and
replacement forward the native profile correspondence policy unchanged.
Native section resolution trims the original parameter domain before reversing
exact traversal. Solid sections require profiles. `guides` is an ordered feature-reference array.
Repeated or overlapping references fail before execution. `surfaceMode` is `ruled` or
`smooth`, `tangentScale` is positive and unitless, and `closed` requires at
least three sections and Sheet output. Lowering preserves order and forwards
one `createLoft` command, without reconstructing geometry. The source evaluator
owns geometric rejection, including currently incomplete curve guide support.
Feature-only section arrays and the old curve-only operation ID are rejected;
there is no compatibility interpretation. Profile trim and continuity controls remain unfinished and
must not be inferred from this registration.

`cad.solid.loft.replace` and `cad.surface.loft.replace` share Loft's section
parser. They require a typed existing/local `body` instead of `name`, and replace
the full supplied section/guide/options payload through Core `setLoft`. They do
not rename, allocate source identities, or change the published body role.
Their output list is empty: callers retain the original source-body identity.
The compiler validates the role; Core additionally requires an actual Loft and
atomically rejects invalid geometry. These are replacement operations, not
partial patches: omitted optional section controls use the documented defaults.

This module owns:

- the qualified `cad.*` operation IDs and version `1` schemas listed here;
- one descriptor, one typed output schema, and one lowerer for each operation;
- CAD-specific validation and conversion of typed semantic values into existing
  high-level `RupaCore` commands;
- fixed prepared-command and generated-source-work estimates for each operation;
- composition rules that realize simple geometry directly and complex geometry
  as bounded programs of the same operations.

It does not own the generic semantic graph model/compiler, persistent ID
allocation, source mutation, project coordinates, publication, result
projection, wire DTOs, access transport, CLI syntax, benchmark cases, Mesh
editing, kernel topology, or renderer behavior. It cannot import Agent,
Project, ProjectAccess, CLI, UI, transport, or benchmark targets.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [package design](../../DESIGN.md) | parent | Dependency and identity-phase rules | Places CADDomain between generic compilation and prepared source execution. | No second vocabulary or authority. |
| [RupaDomainFoundation](../RupaDomainFoundation/DESIGN.md) | depends on | Versioned descriptors, typed semantic values/references, DAG compiler, limits | Direct and program forms resolve through one registry. | CADDomain must not read project coordinates. |
| [RupaAutomation](../RupaAutomation/DESIGN.md) | depends on | Prepared steps, typed local slots, complete receipts, bounded work | Each semantic node lowers to exactly one prepared step and one high-level Core command. | Do not expose the command-builder closure publicly. |
| [RupaCore](../RupaCore/DESIGN.md) | depends on | Server-owned identity allocation and high-level source commands | Core creates exact CAD/Product source and reports complete generated deltas. | No caller-minted Feature, Scene, Component, Pattern, or SketchEntity IDs. |

## Architecture

```mermaid
flowchart LR
    Direct["capability.invoke"] --> Compiler["RupaDomainFoundation compiler"]
    Program["program.execute"] --> Compiler
    Registry["RupaCADDomain registry\none vocabulary"] --> Compiler
    Registry --> Discovery["typed Agent discovery projection"]
    Compiler --> Lowerer["matching CAD lowerer"]
    Lowerer --> Prepared["one CADAPI-A prepared step"]
    Prepared --> Core["high-level RupaCore command"]
    Core --> Source["exact CAD + Product source\nserver-owned IDs"]
```

The registry is a product-composed immutable value. There is no operation
switch in Runtime, Protocol, CLI, or benchmark code.

### Version-1 operation registry

All lengths, angles, points, directions, planes, and transforms are typed
semantic values. Lowerers convert accepted values to canonical Core/Swift-CAD
types only after Foundation has validated schema, unit, reference kind, graph,
and work limits.

| Qualified ID | Required arguments | Declared outputs | Core lowering | Commands / generated-source work |
|---|---|---|---|---:|
| `cad.sketch.line` | `name`, `plane`, `start`, `end` | `curve:.feature`, `scene:.scene` | `createLineSketch` | 1 / 2 |
| `cad.sketch.rectangle` | `name`, `plane`, `center`, positive `width`, positive `height` | `profile:.feature`, `scene:.scene` | centered high-level rectangle sketch | 1 / 2 |
| `cad.sketch.circle` | `name`, `plane`, `center`, positive `radius` | `profile:.feature`, `scene:.scene` | `createCircleSketch` | 1 / 2 |
| `cad.sketch.constrained` | `name`, `plane`, ordered ID-free `entities`, index-based `relations` | `sketch:.feature`, `scene:.scene` | Core `createSemanticSketch` | 1 / 2 |
| `cad.solid.box` | `name`, lower-corner `origin`, positive `width`, `depth`, `height` | `profile:.feature`, `body:.body`, `profileScene:.scene`, `bodyScene:.scene` | one `createExtrudedRectangle` family command retaining sketch plus extrude source | 1 / 5 |
| `cad.solid.cylinder` | `name`, `baseCenter`, nonzero `axis`, positive `radius`, positive `height` | `profile:.feature`, `body:.body`, `profileScene:.scene`, `bodyScene:.scene` | one `createExtrudedCircle` command retaining sketch plus extrude source | 1 / 5 |
| `cad.solid.extrude` | `name`, `profile:.feature`, nonzero `distance`, `direction` | `body:.body`, `scene:.scene` | `extrudeSection` | 1 / 3 |
| `cad.surface.extrude` | `name`, `profile:.feature`, nonzero `distance`, `direction` | `body:.sheet`, `scene:.scene` | `extrudeSection` | 1 / 3 |
| `cad.surface.extrudeCurve` | `name`, `curve:.feature`, nonzero `distance`, `direction` | `body:.sheet`, `scene:.scene` | `extrudeSection` | 1 / 3 |
| `cad.solid.revolve` | `name`, `profile:.feature`, `axisOrigin`, `axisDirection`, `angle` | `body:.body`, `scene:.scene` | `revolveSection` | 1 / 3 |
| `cad.surface.revolve` | `name`, `profile:.feature`, `axisOrigin`, `axisDirection`, `angle` | `body:.sheet`, `scene:.scene` | `revolveSection` | 1 / 3 |
| `cad.surface.revolveCurve` | `name`, `curve:.feature`, `axisOrigin`, `axisDirection`, `angle` | `body:.sheet`, `scene:.scene` | `revolveSection` | 1 / 3 |
| `cad.solid.sphere` | `name`, finite `center`, positive `radius` | `body:.body`, `scene:.scene` | Core `createAnalyticSphere` | 1 / 3 |
| `cad.solid.loft` | `name`, `sections:[{kind,source}]`, `guides:[.feature]`, `surfaceMode`, `tangentScale`, `closed` | `body:.body`, `scene:.scene` | `createLoft` with profile sections | 1 / 3 |
| `cad.surface.loft` | same Loft inputs | `body:.sheet`, `scene:.scene` | `createLoft` with ordered profile/curve sections | 1 / 3 |
| `cad.solid.loft.replace` | `body:.body`, remaining Loft inputs except `name` | none; retains target identity | `setLoft` | 1 / 0 |
| `cad.surface.loft.replace` | `body:.sheet`, remaining Loft inputs except `name` | none; retains target identity | `setLoft` | 1 / 0 |
| `cad.scene.transform` | `scene:.scene`, finite `translation`, `axisPoint`, nonzero `rotationAxis`, `rotation` | none; callers retain the source node output | `setSceneNodeTransform` | 1 / 0 |
| `cad.component.define` | `name`, nonempty ordered `rootScenes:[.scene]` | `definition:.componentDefinition` | `createComponentDefinition` | 1 / 1 |
| `cad.component.instantiate` | `name`, `definition:.componentDefinition`, finite `transform` | `instance:.componentInstance`, `scene:.scene` | `createComponentInstance` | 1 / 2 |
| `cad.pattern.linear` | `name`, `definition:.componentDefinition`, nonzero `direction`, nonnegative `distance`, positive bounded `count` | `pattern:.pattern`, `rootScene:.scene` | one native `createPatternArray` | 1 / `3 + 2*count` |

`.body` is the semantic source-body kind: during staging it binds the generated
Feature plus `.body` output role. It is not evaluated topology `BodyID`.
`profile`, `curve`, and `sketch` are semantic output names whose prepared kind
is `.feature`; their descriptors retain the stricter intended use.

### Constraint value contract

`cad.sketch.constrained` accepts only ordered, ID-free line and analytic-circle
entity values. Relations refer to those entities by zero-based local index;
coincident relations additionally select one endpoint on each line. Supported
relations are coincident, parallel, perpendicular, horizontal, vertical,
equal-length, concentric, and equal-radius. The lowerer never constructs a
`Sketch`, `SketchEntityID`, `FeatureNode`, or `FeatureGraphTransaction`; it
passes the ID-free plan to Core for materialization.

### Benchmark realization mapping

The unchanged 100-case benchmark is a consumer of the universal registry, not
an operation source:

| Category | Count | Semantic realization |
|---|---:|---|
| LIN | 12 | one `cad.sketch.line` |
| REC | 12 | one `cad.sketch.rectangle` |
| CIR | 12 | one `cad.sketch.circle` |
| ANG | 16 | two `cad.sketch.line` nodes |
| BOX | 12 | one `cad.solid.box`, retaining exact sketch plus extrude source |
| CYL | 8 | one `cad.solid.cylinder`, retaining exact sketch plus extrude source |
| CON | 8 | one `cad.sketch.constrained` |
| TRN | 8 | one source operation followed by `cad.scene.transform` |
| CMP | 7 | two or three `cad.solid.box`/`cad.solid.cylinder` nodes |
| SPH | 5 | one `cad.solid.sphere` with exact analytic source |

Angles and compounds do not receive dedicated operations. Rectangle-profile
extrusion and the component/instance/pattern chain prove composition beyond the
fixed benchmark without adding a third public form.

## Contracts and Invariants

1. Every operation ID is qualified exactly as listed and has explicit version
   `1`. Missing or unknown versions fail; no default version is inferred.
2. Each registered descriptor has exactly one lowerer and one output schema.
   Direct invocation and an equivalent one-node program compile to the same
   prepared meaning.
3. Every lowerer emits exactly one prepared step and one high-level Core
   command. Multi-operation meaning is expressed by a semantic program, not a
   hidden lowerer loop or raw feature graph.
4. Persistent identities and Product presentation are Core outputs. Semantic
   inputs contain typed existing references or request-local program references
   only. `BodyID`, `SketchEntityID`, caller-reserved UUIDs, and presentation
   objects are invalid inputs.
5. `cad.solid.sphere` always lowers to the exact analytic sphere command. Mesh,
   faceted, revolve, loft, bounds-only, or unsupported-success substitutes are
   invalid.
6. Native pattern count changes generated work but not semantic node count,
   prepared-step count, Core-command count, or declared output-slot count.
   Occurrence identities remain complete receipt telemetry rather than local
   output declarations.
7. CAD-specific lowerer failures use stable codes `cad.invalidArgument`,
   `cad.degenerateGeometry`, `cad.invalidReference`,
   `cad.referenceKindMismatch`, `cad.unsupportedValue`, or
   `cad.coreCommandRejected`. Foundation-owned unknown-version, graph, value,
   unit, reference, cycle, and limit failures remain Foundation errors.
8. All operations are `.source` / `.sourceMutation`, deterministic for the
   accepted typed input and registry version, and available only when their
   required Core command exists. Registration never reports placeholder,
   benchmark-derived, or partial availability.
9. Product composition validates exact set equality with the IDs in the
   version-1 table. Duplicate, missing, unexpected, or independently projected
   registrations fail before Agent discovery is exposed.

## Runtime Flows

```mermaid
sequenceDiagram
    participant F as Foundation compiler
    participant D as CADDomain registry/lowerer
    participant A as Prepared Automation
    participant C as RupaCore staged authority
    F->>D: validated node + typed arguments/references
    D-->>F: one prepared step + estimates
    F->>A: complete ordered prepared program
    A->>C: one high-level Core command per node
    C-->>A: complete generated source delta
    A-->>F: typed bindings + telemetry
```

## State, Ownership, and Lifecycle

The registry, descriptors, lowerers, and compiled semantic values are immutable
and product-composed. Lowering retains no session, project, coordinate, request,
or result state. Invocation-local local-reference bindings belong to
`RupaAutomation`; persistent identities and source lifetime belong to Core and
Project publication.

## Failure, Concurrency, and Constraints

Lowering is synchronous, pure with respect to project authority, cancellation-
aware through the compiler, and bounded by Foundation's decoded/lowered work
limits plus Automation's prepared-command/generated-work limits. It performs no
I/O, `await`, callback, retry, publication, save, or alternate-route fallback.
Arithmetic used for pattern work and compound semantic estimates is checked for
overflow; an estimate never clamps or expands a pattern into occurrences.

## Verification and Change Impact

CADAPI-C must provide the following falsifiable evidence:

| Invariant | Required counterexample/evidence |
|---|---|
| Registry completeness | Exact set equality for the version-1 IDs; duplicate/missing descriptor, lowerer, output, or version fails composition. |
| Direct/program identity | Every operation's direct form and equivalent one-node form compile to the same prepared command meaning and outputs. |
| Identity ownership | Caller-minted Feature/Scene/Component/Pattern/SketchEntity/Body IDs are structurally absent or rejected; successful receipts contain only Core-generated values. |
| Sketch constraints | Eight accepted relation families plus wrong entity kind, missing/negative/out-of-range/self/duplicate index, ambiguous coincident endpoint, and degenerate entity failures. |
| Exact sphere | Five benchmark centers/radii produce analytic sphere source and exact 8/12/6 B-Rep; wrong center/radius, nonpositive radius, nonfinite input, Mesh, and other-solid substitutes fail. |
| Source fidelity | BOX/CYL preserve their sketch-plus-extrude source and analytic oracle; no primitive or Mesh shortcut silently changes the benchmark target. |
| Composition | ANG uses two lines, TRN uses source plus transform, CMP uses two/three universal solids, and no benchmark-specific operation is registered. |
| Typed chains | Rectangle profile to extrude and Scene to Component Definition to Instance to native Pattern bind through declared output kinds. |
| Compact pattern | Counts at boundary and boundary-plus-one prove fixed semantic/prepared/command/output shape and checked generated-work growth. |
| Dependency boundary | Target/package scans show no Agent, Project, Access, CLI, UI, transport, benchmark, raw graph, or caller-ID dependency. |

Changing an operation ID/version, argument/output kind, estimate, Core command,
or availability requires rechecking Foundation compilation, Automation binding,
Protocol golden fixtures, Runtime discovery, Project publication, and the full
100-case exact-oracle replay.

Constrained Surface creation and replacement accept ordered point objects in
meters, positional tolerance in meters, angular
tolerance in degrees and Performance/Smoothness selection. Replacement takes
a sheet source handle and preserves identity. The lowerer validates units and
shape, then delegates geometric admission and atomic publication to Core.
