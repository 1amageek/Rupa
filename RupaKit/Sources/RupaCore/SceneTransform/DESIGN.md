# Scene Transform

## Purpose and Scope

Child of [RupaCore](../DESIGN.md), no children. Owns what Move, Rotate, Scale
and Duplicate's follow-up move mean as product placement: the transform frame
(pivot point and axes) a selection is moved in, the world-space motion each
kind of input produces, and applying that motion to the selected placements.

## Responsibilities and Boundaries

Owns: pivot resolution (bounding-box center, median of object pivots, the
active object's pivot, a picked pivot), orientation resolution (the active
object's own axes, a picked pivot's axes, the construction plane, the world),
the motion for axis/plane/screen translation, rotation about an axis, scale
by per-axis or uniform factors, and the freestyle two-point forms, and the
`transformSceneNodes` command.

Does not own: which handle the pointer is on or how a drag becomes a distance
(RupaRendering), keys and dialogs (RupaUI), geometry of the moved objects
(Swift-CAD; placement never changes feature geometry).

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RupaCore](../DESIGN.md) | parent | `SceneNodeHierarchy`, `SceneNodeRelativeTransformPlanner` | World motion re-expressed per node | The root cannot move |
| [RupaRendering](../../RupaRendering/DESIGN.md) | used by | `SceneTransformFrame` | Gizmo drawn and measured in the frame | Axes are orthonormal |
| [RupaUI](../../RupaUI/DESIGN.md) | used by | frame resolution, motions, command | Transform modes, keys and dialog | Typed values are frame coordinates |

## Architecture

```text
selection + pivot mode + orientation ──SceneTransformFrameResolver──▶ SceneTransformFrame
drag / typed value / freestyle points ──SceneTransformMotion──▶ world Transform3D
world Transform3D ──transformSceneNodes(ids:worldDelta:compensatingInstances:)──▶ local transforms
```

## Contracts and Invariants

- A frame is a pivot point and a right-handed orthonormal basis. The pivot is
  the selection's world bounding-box center, the mean of the selected objects'
  world origins (median), the active (last selected) object's world origin, or
  a picked point, which also overrides the mode. Axes are the world axes, the
  construction plane's (u, v, normal), a picked pivot's frame, or the active
  object's own axes orthonormalized from its world placement; a degenerate
  basis is a typed failure.
- Motions are world transforms: translation by frame-coordinate components (an
  axis, a plane or all three), rotation by an angle about a frame axis or any
  axis through the pivot, scale by frame-axis factors or one uniform factor
  about the pivot, and the freestyle forms: move from one point to another,
  rotate about the line through two points taking a reference point onto a
  target direction, and scale along the line through two points by a ratio or
  to a length. Zero, non-finite or collapsing inputs are typed failures.
- `transformSceneNodes` applies one world motion to the outermost selected
  nodes (the relative planner). Shared definitions own their root placements as specified in
  [Scene Cloning](../SceneCloning/DESIGN.md); moving a source placement leaves other
  instances unchanged. The legacy `compensatingInstances` argument is retained for
  command compatibility and no longer changes placement semantics.

## Verification and Change Impact

`SceneTransformTests` prove each pivot and orientation mode, every motion form
including freestyle, typed failures, and independent placement keeping
occurrences in place. A change re-checks the gizmo (RupaRendering) and the
transform modes (RupaUI).
