# Angular Dimensions

## Purpose and Scope

This DrawingPages child owns original direction-bound circular paper dimension
sectors. It derives presentation from current annotation anchors and explicit
caller paper radius/tolerance; it does not author a numerical angular station.

## Responsibilities and Boundaries

Exact projected differences, quadrant membership, positive-ray incidence and
smaller-sector orientation belong here. Geometry owns root endpoint isolation
and retained native traversal; Exchange owns bounded paper path publication.
A label's rounded degree value is not the endpoint or sector authority.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Drawing Pages](../DESIGN.md) | parent | Explicit paper layout and current annotation | Supplies the paper law | Map geometry once |
| [Original Root Span](../../../../../../../../occt-parity/swift-CAD/Sources/CADGeometry/OriginalRootSpan/DESIGN.md) | depends on | OriginalCurveRootBoundary and OriginalCurveRootSpan3D | Retains algebraic native cuts | Geometric, source and algebra depths stay independent |
| [Original Affine Word](../../../../../../../../occt-parity/swift-CAD/Sources/CADGeometry/OriginalAffineOperationWord/DESIGN.md) | depends on | Exact rational source action | Keeps radius and paper translation exact | No rounded matrix composition |

## Architecture

```text
current projected anchors + explicit radius/paper law
  -> exact raw differences and oriented sector
  -> native rational quarter circles + original incidence cuts
  -> retained root spans + exact paper action
  -> bounded Exchange path producer -> page strokes
```

## Contracts and Invariants

The unit quarter's original controls are (1,0), (1,1), (0,1), with weights
1,1,2. Its homogeneous law is X=1-t², Y=2t, W=1+t² on [0,1]. Quarter
rotations use exact signed coordinate permutations. A ray's quadrant establishes
positive-ray selection; a unique root of its exact incidence polynomial retains
the direction endpoint. Exact cross and dot products select the smaller sector;
for exact antipodal rays the deterministic presentation is counterclockwise.
Coincident positive rays fail rather than pretending to display a nonzero angle.

All source coordinates, caller radius and paper mapping coefficients are exact
original binary values. Paper translation retains exact source-center times
points-per-meter plus the original translation as rational coefficients. No
atan2, normalized numerical ray or transformed control net is source authority.
The original annotation center/side order matches the existing angle measurement
producer. Current semantic angle measurement must exist before layout.

## State, Ownership, and Lifecycle

Results retain immutable native root spans and one exact paper operation word.
One caller live Exchange accountant owns every work visit and typed allocation;
no budget reset or detached counter is introduced.

## Failure, Concurrency, and Constraints

Invalid/collapsed input, unresolved original root incidence, selected depth or
storage exhaustion, and absent exact endpoint publication fail before page
publication. Original algebra depth controls root isolation; geometric depth
controls chord subdivision. Source nesting remains separate.

## Verification and Change Impact

Deferred behavioral verification covers all four quadrants, axis endpoints,
clockwise and counterclockwise wrap, antipodal and coincident rays, nonbinary
cuts, transformed paper translation, and independent zero/lowered depth caps.
The actual generated page, published DXF/SVG/PDF strokes and current annotation
binding must be checked after SOURCE87; source structure is not runtime proof.

Paper path publication retains the original RootSpan receipt; normalized sampling
fractions are presentation stations only and must not also occupy the scalar
`originalParameters` field reserved for authored native endpoints. The Exchange
writer rejects that mixed authority. Selected native endpoint re-admission is
owned by Geometry; nonnative lower capability failures remain explicit.
