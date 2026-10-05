# Original Mesh Selection

## Purpose and Scope
Child of [RupaCore](../DESIGN.md), no children. Binds a display mesh to its exact
original evaluated topology for A7 current mounted-frame selection.

## Responsibilities and Boundaries
Kernel owns original mesh FaceRun and complete source admission. This immutable
owner retains the evaluated value and selection snapshot with mesh storage;
ViewportScene owns placed occurrence targets and Rendering owns native hits.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RupaCore](../DESIGN.md) | parent | body display mesh | Retains runtime authority | Decode does not restore authority |
| [ViewportScene](../../RupaViewportScene/DESIGN.md) | used by | bound generated topology | Native frame selection | Admit supplied current evaluation first |
| [Kernel selection](/Users/1amageek/.codex/worktrees/occt-parity/swift-CAD/Sources/CADKernel/DocumentTopologySelection/DESIGN.md) | depends on | validateCurrent and subshapeID | Original provenance | Full snapshot equality |

## Architecture
```text
Actual evaluation -> original selection snapshot + retained evaluated value
 -> immutable mesh storage -> placed topology -> current admission -> native hit
 -> checked original face/name -> placed selection target
```

## Contracts and Invariants
No mutable state or pointer escapes. Authority is not serialized as geometry.
Every triangle mapping compares the actual retained original mesh run and stable
name; differing application run data is rejected. Complete current evaluation
admission is required at mounted query publication, including edge/vertex queries.

## State, Ownership, and Lifecycle
Immutable Sendable class retained by mesh storage and topology. Binding equality compares the same complete original source, B-rep,
configuration, body mesh and subshape values as the kernel. Reconstructing an
equal immutable binding does not rebuild a native frame.

## Failure, Concurrency, and Constraints
Malformed mesh, foreign run, missing names, stale source and ambiguous names are
typed failures. COW retains existing admitted values without new tessellation.

## Verification and Change Impact
After source gate, verify actual pointer/rectangle placement, stale source and
same-revision changed mesh, serialized authority loss, duplicate run and missing
name through the mounted native query route. No source-only completion claim.

The sealed binding publicly exposes its original bodyID witness. Mounted
topology admission additionally compares that witness with the selected
presentation part; complete source equality alone cannot admit another
body's per-body triangle ordinals.
