# Drawing Silhouettes

## Purpose and Scope
Child of [DrawingGeometry](../DESIGN.md). Owns caller-live original placed contour
preparation and its scene-bound receipt. Children: none. Foreground-depth visibility
is a separate producer; a silhouette is not a visible/hidden partition.

## Responsibilities and Boundaries
The existing occurrence projection supplies complete current source and actual
body placements. This component consumes those placements without rebuilding
hierarchy or promoting display matrices into original authority. Kernel owns
original body closure, word image, silhouette extraction and exact trim endpoints.
Exchange owns bounded paper path linearization and format provenance.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [DrawingGeometry](../DESIGN.md) | parent | current original occurrence projection | Supplies original scene binding | Preserve complete current source |
| [DrawingPages](../DrawingPages/DESIGN.md) | used by | retained contour receipt | Composes one paper law | Never replace exact cuts with samples |
| [BRepDrawing](/Users/1amageek/.codex/worktrees/occt-parity/swift-CAD/Sources/CADKernel/BRepDrawing/DESIGN.md) | depends on | placed silhouettes | Owns original geometry and trim partition | Lower unsupported source families propagate |
| [Exchange](/Users/1amageek/.codex/worktrees/occt-parity/swift-CAD/Sources/CADExchange/BRepDrawingExchange/DESIGN.md) | depends on | caller-live accounting and path writer | Shares the complete page allowance | No copied allowance or fresh ceiling |

## Architecture
```text
current occurrence projection -> original placements -> body closure/word image
 -> original normal-zero atlas -> exact face trim -> retained contour receipt
 -> bounded paper path -> immutable page -> format writer
```

## Contracts and Invariants
One SurfaceSilhouetteUsage persists across every placement, trim, refinement and
projection. Its external admission retains the SAME DrawingExchangeUsage owner.
Work/cells/bytes and independent geometric/source/algebra capabilities are caller
owned. Face/span capacities apply to the complete invocation. The explicit entity
capacity applies to each smallest body closure; source control and boundary
capacities pass unchanged to each lower original law. Aggregate bytes/work remain
shared across every closure and lower law. Tracking,
receipt arrays and original body closures are admitted before allocation.
Algebraic endpoints, contact stations and whole coincident domains remain retained;
no empty array substitutes for an unresolved contour or hidden-line result.

## State, Ownership, and Lifecycle
Usage and source arrays are immutable retained owners behind common Mutex counters.
The invocation token rejects a foreign page accountant. The completed receipt
retains the original occurrence projection and each actual placed body receipt.
No display cache or independently supplied document manufactures source binding.

## Failure, Concurrency, and Constraints
Invalid policy, stale source/placement, cancellation, resource exhaustion and lower
proof failures propagate before publication. Extraction and format publication
are synchronous; callbacks retain the shared accountant and perform no I/O while
its Mutex is locked. All original zero families must be retained or explicitly fail.

## Verification and Change Impact
Deferred until all source implementation: public Native generate/export commands
with reflected/nonuniform/multiple occurrences, exact algebraic trims and contact
points, source changes, foreign accountant, independent zero depth caps and late
atomic failure. This source composition alone is not D1 completion evidence.

Exchange's DrawingSilhouetteAdmission issues SurfaceSilhouetteUsage exactly once
and binds both its original local accounting owner and external page admission.
The contour token retains this issuer; equal limits or independently recreated
callbacks do not establish invocation identity. Failed issuance is not reset.

The caller explicitly supplies positive maximumParameterWidth as an exact native
parameter precision; paper deviation or scene units do not infer this bound.
Page publication retains the exact spans and both accounting owners. Contacts,
algebraic atlas/singular events and collapsed sources now receive original
point provenance through the Exchange point carrier. Stored algebraic roots are
refined under explicit native precision before projection; insufficient paper
precision fails. These events are not omitted. Visibility remains separate.

The explicit projectedContacts preparation operation retains lower exact native
curve/silhouette pair partitions with the same issuer/accounting owner. It
consumes the current placed projection and complete silhouette packet; source
cut expressions are never replaced by outward midpoint doubles. This is a
visibility prerequisite only, with point/trim/overlap/LOS coverage still required
before any visible/hidden label. Contour-only publication stays a separate law.
