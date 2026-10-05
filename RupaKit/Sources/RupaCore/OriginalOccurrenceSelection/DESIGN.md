# OriginalOccurrenceSelection

## Purpose and Scope
RupaCore child owning the original visible occurrence and source-node authority retained by SelectionTarget.

## Responsibilities and Boundaries
SceneNodeID remains the authoring/operation owner. OccurrenceID distinguishes placed members of a component instance, and sourceSceneNodeID identifies the original presented body. This component resolves the current original hierarchy; it never infers occurrence membership from render bounds.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RupaCore](../DESIGN.md) | parent | selection publication | Original document authority | Persisted selection is revalidated |
| [OriginalMeshSelection](../OriginalMeshSelection/DESIGN.md) | coordinates with | current evaluated topology binding | Geometry authority is independent of placement identity | Both must pass |

## Architecture
```text
current original scene hierarchy -> visible occurrence + source body
    -> hit / rectangle -> SelectionTarget -> selection / hover / highlight
        -> saved target -> original hierarchy revalidation
```

## Contracts and Invariants
An occurrence-bearing target must retain its source node, exact occurrence owner, and optional original source feature. Current hierarchy resolution rejects deleted, hidden, foreign-owner, foreign-source and changed-feature receipts. Two bodies sharing an instance owner remain distinct targets. Legacy node-only targets retain whole-owner selection semantics. A current click additionally checks the full displayed placement and original evaluation mesh through the existing native admission path.

## Failure, Concurrency, and Constraints
Resolution throws typed EditorError. Decode rejects half-authored occurrence/source pairs. Mutable SelectionModel keeps existing value ownership; shared publication remains under its existing owner isolation. Hierarchy preparation is reused once per selection batch where possible.

## Verification and Change Impact
Deferred checks must cover multi-body/nested instances, same source placed twice, hidden/locked members, stale source generation/mesh/placement, rectangle de-duplication, exact per-occurrence highlights, save/reload, delete/prune and operation source resolution. Native/WASM source consumers keep identical Sendable values.

### Original body-bound subshape selection

SelectionTarget optionally retains original sourceBodyID with its original
sourceFeatureID and occurrence binding. Object selection remains at the
feature occurrence scope; face/edge/vertex selection uses the body witness
to choose the exact presented part and original B-rep incidence. Native
serialization preserves the witness. Current evaluation validation rejects
a missing/foreign body or a subshape outside that body's original topology.

OriginalBodyTopologyMembership derives the exact body incidence from original
shells, face loops, coedges and edge endpoints. It rejects missing original
records; current-target pruning reuses one immutable membership per selected
body and requires the feature body witness and generated reference to agree.
