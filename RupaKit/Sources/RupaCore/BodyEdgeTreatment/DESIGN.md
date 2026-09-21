# Body Edge Treatment

## Purpose and Scope

Child of [RupaCore](../DESIGN.md), with no children. Owns the translation of
selected CAD edges into native fillet, chamfer and G2 blend features.

## Responsibilities and Boundaries

Core resolves source identity and preserves occurrence placement. Swift-CAD
constructs and validates the B-rep. This component does not rewrite the source
sketch, approximate a selected edge by a bounding-box corner, or tessellate.

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Core](../DESIGN.md) | parent | source transactions | Allocates feature and presentation identities. | Workspace owns publication and Undo. |
| [Modeling UI](../../RupaUI/Modeling/DESIGN.md) | used by | preview/apply | Supplies selected generated edges and a physical amount. | Display subdivisions do not define the operation. |
| [CADModeling](../../../../swift-CAD/Sources/CADModeling/DESIGN.md) | depends on | native edge blend evaluators | Constructs complete topology or fails. | Current single-edge planar envelope remains explicit. |

## Architecture

```text
UI draft -> EditorCommand -> current stable edge reference
    -> native FeatureOperation -> existing feature graph staging
    -> exact candidate evaluation -> Workspace publication / Undo
```

## Contracts and Invariants

- A request selects exactly one generated edge of an editable body. Unsupported
  multi-edge blends are refused, not partially applied.
- Radius/distance must be finite and greater than modeling tolerance. The
  kernel owns geometric feasibility and never falls back to sketch editing.
- The stable reference is resolved from current exact topology and must belong
  to the selected occurrence. Missing, stale, locked and non-body inputs fail.
- The result retains its source occurrence's parent, transform and material.
  Input feature geometry remains unchanged; the new feature consumes its body.
- Preparation produces a feature transaction, not a successful geometric result.
  CADDocumentStore/Workspace evaluate the staged candidate before successful
  publication and roll back both source and metadata on failure. No duplicate
  candidate evaluation is added inside preparation.

## State, Ownership, and Lifecycle

All values are request-local. No caches, tasks or shared mutable state are added.

## Verification and Change Impact

`Tests/RupaCoreTests/BodyEdgeTreatmentTests.swift` owns all box-edge orientations,
exact cylindrical fillet geometry, chamfer volume, source preservation,
round-trip and invalid-radius/selection atomicity. Modeling draft tests own
command forwarding and UI validation. Workspace integration owns Undo and
preview cancellation. Changes require reviewing Core dispatch and Modeling UI.
