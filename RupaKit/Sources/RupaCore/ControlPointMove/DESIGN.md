# Control Point Move

## Purpose and Scope

Child of [RupaCore](../DESIGN.md), no children. Owns what Move Control Point's
Proportional and Mirror options mean for B-spline surface control points: which
control points of a surface move, by how much, and where a mirrored move lands.

## Responsibilities and Boundaries

Owns: the falloff weight of every control point from the moved selection
(`SurfaceControlPointMoveOptions.Proportional`), the mirror counterpart of a
control point across a construction-plane axis, the combined displacement of
each control point, and the `moveSurfaceControlPointsProportionally` command.

Does not own: which control points are selected or how a drag becomes a delta
(RupaRendering, RupaUI), the surface geometry and its validation (Swift-CAD
`BSplineSurface3D`), PolySpline vertices (their net is a mesh, not a U×V hull).

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RupaCore](../DESIGN.md) | parent | `SurfaceControlPointSelectionTargetResolver`, `SceneNodeHierarchy` | Selection references resolve to B-spline control point indices; the scene node places the surface | A surface must be presented by exactly one scene node for a mirror |
| [RupaUI](../../RupaUI/DESIGN.md) | used by | options, command | The control point panel edits the options; a drag commits the command | Deltas are in the surface's own coordinates |

## Architecture

```text
targets (selection order, last = active) + delta + options
  ──SurfaceControlPointSelectionTargetResolver──▶ (feature, u, v) per target
  ──SurfaceControlPointProportionalMove.displacements──▶ [feature: [u,v → Vector3D]]
  ──BSplineSurfaceFeature control net update──▶ replaceFeature + validate (all or nothing)
```

## Contracts and Invariants

- Distance is measured along the hull, not in space: between control points
  (u₀, v₀) and (u, v) it is r = √((|u−u₀|/falloffU)² + (|v−v₀|/falloffV)²) in
  control-net steps, and the weight is (1 − r²)² for r < 1, else 0. Falloffs are
  finite and positive.
- None moves exactly the selected control points by the delta. All moves every
  control point of each touched surface by the delta times its largest weight
  from any selected control point (selected points weigh 1). Selected moves
  only the selected control points, weighted from the active (last selected)
  control point of their surface.
- Mirror X, Y or Z reflects across the plane through the construction plane's
  origin whose normal is its u, v or normal axis, carried into each surface's
  coordinates through the one scene node that presents it. Each moved control
  point's counterpart is the control point of the same surface at its reflected
  position (within the modeling distance tolerance); it moves by the reflected
  delta with the same weight. A control point on the plane is its own
  counterpart and keeps only the in-plane part of the delta. A moved control
  point with no counterpart is a typed failure; where both sides weigh a point,
  the larger weight wins.
- The command resolves every target, computes every displacement and validates
  every surface before replacing any feature; any failure leaves the document
  unchanged. Targets that are not B-spline surface control points are refused.

## Verification and Change Impact

`SurfaceControlPointProportionalMoveTests` prove each proportional mode's
weights on a control net, falloff limits, the mirror counterpart and on-plane
projection, the missing-counterpart and non-B-spline refusals, and the command
moving a document's surface atomically. A change re-checks the control point
panel and drag commit (RupaUI).
