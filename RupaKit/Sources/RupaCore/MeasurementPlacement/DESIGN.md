# Measurement Placement

## Purpose and Scope

Child of [RupaCore](../DESIGN.md), no children. Owns how a Measure Distance
dimension is placed and saved: the construction-plane axis a dimension measures
along, the dimension and extension lines drawn for it, anchors that follow the
geometry a measured point was snapped to, and where saved measurements live in
the scene.

## Responsibilities and Boundaries

Owns: `MeasurementDimensionGeometry` (value, dimension line, extension lines and
label anchor from two points, an optional axis and a label position), the axis
choice from the cursor, `MeasurementAnchor.associative(for:)` (snap → topology or
sketch anchor), and the "Measurements" group saved annotations are placed in.

Does not own: resolving anchors to points (`MeasurementAnchorWorldPointResolver`,
through Swift-CAD edge queries), picking points and the tool's phases
(RupaRendering), keys and panel (RupaUI).

## Related Designs

| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [RupaCore](../DESIGN.md) | parent | `MeasurementAnnotation`, `MeasurementAnchor`, `SnapCandidate` | Saved annotations and their anchors | `placementAxis` nil means straight-line distance |
| [RupaRendering](../../RupaRendering/DESIGN.md) | used by | geometry, axis choice, associative anchors | Live placement and saved drawing share one geometry | — |

## Architecture

```text
start, end, cursor, view normal, CPlane axes ──placementAxis──▶ axis or nil (straight)
start, end, axis, label ──MeasurementDimensionGeometry──▶ value, dimension line, extension lines, label anchor
snap candidate ──associative(for:)──▶ topology edge/vertex/face or sketch anchor, else picked placement
```

## Contracts and Invariants

- The value of an axis dimension is |(end − start) · axis|; of a straight one
  |end − start|. The dimension line passes through the label position, parallel
  to the axis (or to end − start), between the projections of the two points;
  extension lines join each point to its end of the dimension line.
- The cursor chooses, among the construction plane's u, v and normal axes along
  which the points differ and that are not seen end-on, the axis most
  perpendicular on screen to the cursor's offset from the midpoint; with no such
  axis the dimension is straight.
- A point snapped to an edge start, end or midpoint anchors to that edge at
  parameter 0, 1 or ½; to a vertex or face center, to that vertex or face; to a
  sketch line, arc or spline end or midpoint, to that curve's parameter; to a
  circle or arc center, sketch point or spline control point, to that sketch
  reference. Such anchors follow edits of the geometry; other points keep the
  placement they were picked under.
- A saved annotation without a node goes into a "Measurements" group under the
  first document root, created on first use.

## Verification and Change Impact

`MeasurementPlacementTests` prove the axis and straight values and lines, the
axis choice for cursors along each screen direction, associative anchors
resolving after the measured geometry changes, and the Measurements group. A
change re-checks the Measure tool (RupaRendering) and drawing projection.
