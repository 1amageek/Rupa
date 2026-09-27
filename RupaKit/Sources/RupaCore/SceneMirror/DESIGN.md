# Scene Mirror

## Purpose and Scope

Child of [RupaCore](../DESIGN.md), no children. Owns what Mirror means for
selected objects: the mirror plane in world space, the Cut down mirror plane,
Union halves and Make Instances options, and turning them into Swift-CAD
mirror features and scene objects.

## Responsibilities and Boundaries

Owns: `SceneMirrorPlane` (a world plane; the reflection lands on the side its
normal points to) built from a construction-plane axis and sign, a picked face
point and outward normal, or a freestyle line; `SceneMirrorOptions`; and
`mirrorSceneNodes(ids:plane:options:)`, which decides per selected object which
mirror features, copies and instances to create.

Does not own: the exact geometry of cutting, reflecting and joining bodies
(Swift-CAD `MirrorFeature` with `output` and `cutsAtPlane`), exact face points
and normals (Swift-CAD, through `PlacedSurfacePointResolver`), keys and the
panel (RupaUI), copying objects (SceneCloning).

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RupaCore](../DESIGN.md) | parent | `SceneNodeHierarchy`, `appendTopologyEdit` | Each object's feature is replaced by its mirror feature | Locked, instance-owned and non-body objects are refused |
| [SceneCloning](../SceneCloning/DESIGN.md) | depends on | `placeSceneNodes` | Copies an object in place, or places an instance at the reflection | Instances may carry a reflecting placement |
| [RupaUI](../../RupaUI/DESIGN.md) | used by | plane builders, options, command | The Mirror session keys and panel | Freestyle points are world points |

## Architecture

```text
axis+sign / face point+normal / freestyle line ──SceneMirrorPlane──▶ world plane
world plane ──object world transform⁻¹──▶ plane in the body's coordinates
options ──per object──▶ MirrorFeature(output, cutsAtPlane) and/or copy / instance
```

## Contracts and Invariants

- The reflection lands on the side the plane normal points to. An axis plane
  passes through the construction plane origin with the construction plane's
  u, v or normal axis as normal, negated for Shift. A picked face gives the
  plane tangent to it at the point with the outward normal. A freestyle line
  gives the plane containing the line and the construction plane normal, with
  normal = construction normal × line direction.
- Cut down mirror plane keeps, for each object, only its material on the side
  opposite the normal. Union halves replaces the object's feature with one
  body joining the kept material and its reflection. Make Instances keeps the
  object (cut when cutting) and adds a component instance placed at the world
  reflection. Otherwise the object is kept (cut when cutting) and an
  independent copy of it is replaced by the reflection alone. Union halves and
  Make Instances together are refused.
- A body placement that shears or scales unevenly has no mirror plane in the
  body's coordinates and is refused; so are locked objects, objects owned by an
  instance and non-body objects outside Make Instances.
- A sheet body mirrors to a sheet: the mirror feature takes its target's output
  role from `FeatureNodeFactory`. Union halves sews a sheet meeting the plane
  along an edge to its reflection, and keeps a sheet clear of the plane beside
  its reflection. Swift-CAD refuses a sheet that may cross the plane, and Rupa
  refuses cutting a sheet, since the kernel cannot split a sheet at the plane
  yet (`FIXME(INCOMPLETE_IMPLEMENTATION)` in `mirrorableBody`).
- The command returns the new objects (copies or instances) or, for Union
  halves, the mirrored objects, and is one undoable source command.

## Verification and Change Impact

`SceneMirrorTests` prove each plane builder, the copy, cut, union and instance
outputs by the evaluated volumes and bounds of the result bodies, a placed
object mirrored across a world plane, a sheet copied and joined across the
plane with its cut refused, and the refusals. A change re-checks the
Mirror session (RupaUI) and Swift-CAD's mirror feature contract.
