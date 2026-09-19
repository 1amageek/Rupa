# Spatial Path Editing

## Purpose and Scope

Child of [RupaCore](../DESIGN.md). Creates and edits XYZ polyline/Bezier sources.
No children. Existing cube and object transformation contracts are unchanged.

## Responsibilities and Boundaries

Owns source conversion, feature identity and Product synchronization. Swift-CAD
owns path geometry and tangent semantics. Project source transactions own
publication, preview, cancel and Undo; UI owns selection and handle presentation.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RupaCore](../DESIGN.md) | parent | document mutations | One source authority | Edits publish atomically |
| [SpatialPath](../../../../swift-CAD/Sources/CADIR/SpatialPath/DESIGN.md) | depends on | validated edits | Geometry and tangent semantics | Knots use stable IDs |

## Architecture

```text
EditorCommand -> DesignDocument copy -> SpatialPathFeature edit
              -> validated CAD/Product -> existing Project transaction
```

## Contracts and Invariants

Creation allocates source and Scene identities. Editing retains feature and knot
identities except explicitly inserted/deleted knots. Conversion is explicit and
freezes current evaluated coordinates in the sketch's 3D plane, without changing
Scene placement. Conversion rejects profile dependents and sketch-entity
references that would become invalid; it never drops dependent geometry.
Mutations validate a complete candidate before assigning it. A failed edit does
not change CAD source or Product. Object metadata is updated for every occurrence
of the edited source, not just the first instance.

## Verification and Change Impact

RupaCoreTests spatial-path tests cover conversion, source edit failure atomicity,
identity and evaluated XYZ. Project tests own preview/cancel/Undo/Redo. Native
Rendering tests own hit targets, screen-to-world input and live output.
