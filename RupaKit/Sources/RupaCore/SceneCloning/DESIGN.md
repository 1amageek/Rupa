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
- A copied component instance is a new instance of the same definition with
  the same instance transform. The fragment carries each instance's definition
  with its content (extracted in the world frame); where the destination lacks
  the definition, the content is inserted hidden at its world placement under
  the first document root and a new definition with a unique name names it.
  A copied authored mesh (a mesh object or a mesh representation of any copied
  object) is a new asset with the same mesh under a new source identity, and
  the copy's representations and selection name the new asset and fresh
  representation IDs, so no copy shares a mesh with its source.
- Pattern array outputs and document roots are refused with a typed error; their
  sharing semantics are not copies. A copied construction plane is a new plane
  source named "<name> Copy" (numbered when taken). A saved measurement whose
  annotation node is copied travels with it: anchors on copied nodes name the
  copies (scene node, feature, generated subshape, and the occurrence resolved
  in the new scene), anchors on geometry outside the copy keep measuring it, and
  world positions, the label and the placement axis move with the copy.
  `ProductMetadata.sceneCopyRefusal` is the one statement of these refusals:
  extraction throws it and every UI control that offers copying reads it.
  Independent-copy pattern outputs copy authored meshes too: the synchronizer
  carries the document's mesh assets, a definition's identity includes the
  content of the meshes it presents, an output may copy meshes alone, and
  removing outputs removes the mesh copies only they presented.
  `SceneCopyCompletenessTests` owns measurements, construction planes, mesh
  arrays and instances pasted into another document.
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
- Surface points and normals for placement come from `PlacedSurfacePointResolver`:
  the viewport names the face its pick landed on, the pick is taken into the
  occurrence's source frame, Swift-CAD's `SurfaceQueryEvaluator.outwardFrame`
  returns the nearest exact point of that face with its outward normal (the
  kernel owns face orientation), and both are placed back into the world.

## Verification and Change Impact

`SceneCloningTests` prove: in-place duplicate evaluates to the same geometry at
the same world placement under a transformed parent; copies are independent
(editing the copy's source leaves the original unchanged); carried presenters
are hidden and placed; face material bindings and edit sources are copied with
remapped identities; cross-document insertion adds parameters and materials and
refuses a conflicting parameter without mutation; refused selections throw;
copied instances and authored meshes get new identities and share nothing.
Pattern array tests continue to own independent-copy outputs. A change here
re-checks pattern arrays, Duplicate, Place and Paste.
