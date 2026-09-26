# Scene Cloning

## Purpose and Scope

Child of [RupaCore](../DESIGN.md), no children. Owns the one way Rupa copies
product objects: extracting scene subtrees with everything their geometry needs
into a self-contained `SceneFragment`, and inserting copies of a fragment at
placements with fresh identities. Duplicate, Place, Paste with Placement and
independent-copy pattern outputs all copy through it.

## Responsibilities and Boundaries

Owns: the copied feature closure, identity maps, scene-tree cloning, placement
of copied roots, transfer of referenced parameters and materials, copying of
the side tables keyed by copied features or nodes (face material bindings,
Bridge Curve and joined-curve edit sources), and removal of copied outputs with
those side tables.

Does not own: which features an operation references (Swift-CAD's
`FeatureNode.remappingFeatureReferences` decides and remaps them), where copies
go and how many (the command or pattern source decides), pasteboard transport
(RupaUI), or geometric validity of the copy (document evaluation).

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RupaCore](../DESIGN.md) | parent | EditorCommand, ProductMetadata validation | Commands call the component inside one document mutation | Metadata must validate after insertion |
| [CADIR](../../../../swift-CAD/Sources/CADIR/DESIGN.md) | depends on | `FeatureNode.remappingFeatureReferences`, `referencedParameterIDs` | Kernel owns operation references | A reference outside the closure is a typed failure |
| Pattern arrays (RupaCore) | used by | extract with a reference frame, insert detached | Independent-copy outputs | Output removal must remove side tables too |
| [Modeling UI](../../RupaUI/Modeling/DESIGN.md) | used by | `SceneFragment` payload | Copy/Paste with Placement transport | The payload is data; insertion validates it |

## Architecture

```text
selected roots ──SceneFragmentExtractor──▶ SceneFragment (Codable, document independent)
                    │ feature closure (inputs + kernel-listed references)
                    │ carried presenters of closure features outside the roots
                    │ parameters (transitive), materials, side tables
                    ▼
SceneFragment ──SceneFragmentInserter(placements, parent)──▶ copies in DesignDocument
                    │ per copy: FeatureID map → kernel remap, SceneNodeID map
                    │ root local = inverse(parent world) · placement · fragment placement
                    ▼
            SceneFragmentInsertion (root IDs per copy, feature IDs)
```

## Contracts and Invariants

- A fragment is self-contained: every feature any fragment feature or node
  references is in the fragment, ordered as in the source graph; every
  parameter referenced by a feature (transitively through parameter
  expressions) and every material referenced by a node or binding is included.
- Roots are the selected nodes minus any whose ancestor is also selected, in
  scene order. Each root carries its placement in the extraction reference
  frame (world for Duplicate, Place and Copy; the first root's parent frame for
  pattern definitions).
- A closure feature presented by a node outside the selected subtrees is
  carried as a hidden node under the first copied root, keeping its placement
  relative to the copy, so every copied feature keeps one presenting node and
  no copy is drawn unplaced.
- Component instances, pattern array roots and outputs, authored meshes,
  construction references and document roots are refused with a typed error;
  their sharing semantics are not copies. `ProductMetadata.sceneCopyRefusal`
  is the one statement of these refusals: extraction throws it and every UI
  control that offers copying reads it.
- Insertion never reuses an identity: each copy gets new FeatureIDs (remapped
  by the kernel), SceneNodeIDs and side-table IDs. Face material bindings follow
  their node and face subshape; edit sources follow their sketch feature.
- A parameter already present with the same definition is reused; a parameter
  present with a different definition is a typed conflict and nothing is
  inserted. A material already present with the same value is reused; one
  present with a different value is added under a new MaterialID and the copy
  refers to it.
- Placement: a copied root's local transform is
  `inverse(parentWorld) · placement · fragmentPlacement`; a singular or
  non-affine result is a typed failure.
- Removal of outputs removes the nodes, features and every side-table entry
  keyed by them.
- `SceneNodePlacementSpec` turns two picked references into the world
  transform Place and Paste apply: the source point lands on the destination
  point, the source surface normal faces the destination normal (or points
  along it when flipped; the up axis stands in for a missing source normal and
  stays vertical for a missing destination normal), then a spin about the
  destination normal and a uniform scale about the destination point.
- `placeSceneNodes` with `.componentInstance` output reuses the component
  definition whose roots are exactly the selection (creating one otherwise) and
  creates one instance per placement whose transform carries the roots' parent
  frame, so each instance shows the objects at the placement a copy would take.
  Objects under different parents are refused: one instance has one frame.
- A placement Boolean makes each placed copy the tool of a `createBoolean`
  with the body the destination lies on (the first copy with the target, each
  later copy with the previous result); a copy must contain exactly one body,
  the copies are hidden once consumed, and component-instance output cannot be
  combined.
- Surface normals for placement come from `PlacedSurfaceNormalResolver`: the
  pick is taken into the occurrence's source frame, projected with Swift-CAD's
  surface query onto the presented body's faces, and the nearest face's normal
  is oriented by the face and placed back into the world.

## Verification and Change Impact

`SceneCloningTests` prove: in-place duplicate evaluates to the same geometry at
the same world placement under a transformed parent; copies are independent
(editing the copy's source leaves the original unchanged); carried presenters
are hidden and placed; face material bindings and edit sources are copied with
remapped identities; cross-document insertion adds parameters and materials and
refuses a conflicting parameter without mutation; refused selections throw.
Pattern array tests continue to own independent-copy outputs. A change here
re-checks pattern arrays, Duplicate, Place and Paste.
