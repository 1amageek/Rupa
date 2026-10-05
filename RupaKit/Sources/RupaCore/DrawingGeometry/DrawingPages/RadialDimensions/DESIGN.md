# Radial Dimensions

## Purpose and Scope
Child of [DrawingPages](../DESIGN.md), with no children. Owns one generated-edge or current evaluated sketch-circle
radius/diameter annotation's current original source binding and projected proposals.

## Responsibilities and Boundaries
Stable topology and original circular geometry producers own identity and metric
proofs. This child selects the actual visible body occurrence from the current
projection receipt, retains its original operation word, and validates proposal
uncertainty against caller paper deviation. Glyphs and strokes stay in the parent.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [DrawingPages](../DESIGN.md) | parent | paper mapping and current publication | Composes annotations and strokes | Same live usage |
| [OriginalCircularMeasurement](/Users/1amageek/.codex/worktrees/occt-parity/swift-CAD/Sources/CADGeometry/OriginalCircularMeasurement/DESIGN.md) | depends on | original plane Gram and singleton boundary | Supplies source-bound metric | Elliptic images fail |
| [OriginalGeometryQuery](/Users/1amageek/.codex/worktrees/occt-parity/swift-CAD/Sources/CADKernel/OriginalGeometryQuery/DESIGN.md) | depends on | bounded original edge receipt | Resolves stable source | No display cache authority |

## Architecture
```text
current generated edge ID OR evaluated sketch entity -> bounded original curve/native interval
current original occurrence -> retained placement word
 -> original circular measurement -> projected bounded proposals
 -> current annotation + retained source receipt -> paper strokes/label
```

## Contracts and Invariants
A single generated-edge annotation resolves the original edge, selects one actual
visible occurrence and uses the native edge start station as its radius boundary.
Center and radius come from the source-plane conformality proof, never an edge
midpoint, cached display summary or distance between rounded candidates. Multiple
coedges may share the same body/occurrence, but ambiguous occurrences fail.
The center/boundary proposals carry a whole outward projection box. Total proposal
error is paid within one quarter of original caller paper deviation; the parent's
rounding admission remains separate. Diameter uses twice the original radius, with
outward floating arithmetic included. All source/subdivision/algebra ceilings and
work/BYTES callbacks come from the same live DrawingExchangeUsage.

## State, Ownership, and Lifecycle
Immutable Sendable receipts retain original circular law and current projection
binding. The page holds receipts through publication. Temporary capacities are
admitted before allocation. No independent allowance or mutable source cache exists.

## Failure, Concurrency, and Constraints
Noncircular sources, ambiguous/stale binding, insufficient precision or selected
caps fail before page publication. Normalized edge-parameter anchors retain exact directed native gain/lower offset
and original fraction through the circular measurer. Single sketch-curve anchors bind the unsuppressed current sketch feature/entity to exactly one evaluated curve with matching original source identifiers. Constraint solving and sketch-plane construction remain with the original evaluation producer. The receipt pays only original-law preparation, never display validation. Sketch occurrences use the bounded source hierarchy and actual saved-view visibility; absent presenting nodes preserve the existing unplaced world-source meaning. Sketch receipts retain feature/entity IDs and no invented body ID.

## Verification and Change Impact
Deferred behavioral coverage must check native circle/arc, reflected/XY conformal
placements, anisotropic ellipse refusal, stale stable references, multiple visible
occurrences, lowered work/bytes/depth, radius versus diameter and paper precision.
Change impact reaches original circular query, current occurrence projection and
page source retention. Source phase makes no runtime/verification claim.

The page resolves single circular annotations directly through this original
producer and excludes them from legacy anchor projection. A preceding legacy
normalized station query is not a paid original-law receipt. Label placement is
manual original world position or the certified boundary proposal, followed by
the parent layout service.

Generated-edge identity is decoded from the authored anchor's canonical subshape
and component strings, then bound to the current projection's source feature,
scene node and occurrence. The bounded current generated-edge issuer reads the
current index under the same live admission. This route does not construct a
TopologySnapshot or invoke display metrics/legacy whole-BRep validation.

A generated current ID is consumed by resolveCurrentOriginalGeometry directly.
Historical stable signature issuance remains a distinct public route; its
distinct-endpoint rule is not weakened to accommodate a closed circular edge.
The current lookup checks live feature, original lineage and actual indexed edge
before paying curve/trim source preparation.
