# Gear Editing

## Purpose and Scope

Child of [RupaCore](../DESIGN.md), no children. Creates and replaces native
gear source through existing EditorCommand staging.

## Responsibilities and Boundaries

Owns source and product-node mutation. The native kernel owns geometric
feasibility; Project owns staging, evaluation, publication and Undo. Replacing
dimensions preserves feature, occurrence and representation identity.
Dimension replacement uses the existing validated graph-stable transition,
preserving parameter dependency updates without revalidating unrelated source.
The store retains the returned source validation after its normal commit step;
stale source validation is refused before mutation.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Core](../DESIGN.md) | parent | EditorCommand | Existing state owner | No direct UI mutation |
| [Native source](../../../../swift-CAD/Sources/CADIR/InvoluteGear/DESIGN.md) | depends on | Gear dimensions | Parameter-aware source | No mesh fallback |
| [Modeling UI](../../RupaUI/Modeling/DESIGN.md) | used by | Preview/apply | Creation and reediting | Runtime integration remains unverified |

## Architecture

```text
gear draft -> EditorCommand -> candidate DesignDocument
    -> existing project preview/evaluation -> Apply / Undo
```

## Contracts and Invariants

Creation adds one body feature and one product occurrence. Editing replaces
only the matching gear operation. Invalid source does not mutate the document.
Geometric failure must prevent staged publication through existing Project.

## Verification and Change Impact

After implementation assembly, verify creation, reediting, parameter changes,
invalid root geometry, Undo and native document round-trip with actual geometry.
