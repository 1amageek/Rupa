# Original Mass Properties

## Purpose and Scope
Child of [RupaCore](../DESIGN.md), no children. Owns read-only original CAD solid
mass composition for selected or whole-document placed occurrences.

## Responsibilities and Boundaries
SceneNodeHierarchy owns occurrence expansion and placement. CADKernel owns
original volume moments, density source resolution and SI inertia composition.
This component binds those contracts to complete current source and selected
scene owners. It does not derive density from viewport appearance or integrate
render triangles.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RupaCore](../DESIGN.md) | parent | current source admission | Source and selected scene owner | Generation plus complete source equality |
| [CADKernel mass properties](/Users/1amageek/.codex/worktrees/occt-parity/swift-CAD/Sources/CADKernel/GeometricMeasurement/DESIGN.md) | depends on | original moment and density evaluator | Physical SI results | Lower integration budget and failure propagate |

## Architecture
```text
Current source + whole-object selection -> source-admitted exact evaluation
 -> occurrence expansion -> original solid body identity + affine world placement
 -> physical source density + original moments -> SI mass/inertia + occurrence IDs
```

## Contracts and Invariants
Each selected owner must exist; subshape selection is not a whole solid mass
request. Repeated parts contribute once per distinct occurrence. Geometry uses
internal metres; there is no document display-unit rescaling. An explicit density
override applies only to the named original body; absent overrides require the
kernel physical source density. Finite nonsingular affine placement admits rotation, reflection, scale and
shear using the original moment transport. The kernel must prove the outward
determinant excludes zero before transporting density and moments. No partial occurrence list or missing-density success is returned.

## State, Ownership, and Lifecycle
Invocation-local immutable evaluation, occurrence and component values. No
shared state, pointer or render resource. Source equality precedes use.

## Failure, Concurrency, and Constraints
Caller specifies component capacity and original moment accuracy. Capacity is
checked before component allocation; cancellation occurs at occurrence/body
boundaries. Unknown source IDs, incomplete current evaluation, non-solid selected
CAD outputs, singular or unproved placement and lower convergence failures remain typed.

## Verification and Change Impact
After all source implementation, verify placed repeated parts, selection of one
instance, non-origin inertia, missing density, same-revision stale evaluation,
capacity failure, nonuniform scale/shear, reflection and singular placement
refusal through the public service. Lower general curved-moment convergence
remains the kernel owner's required source and verification boundary.
