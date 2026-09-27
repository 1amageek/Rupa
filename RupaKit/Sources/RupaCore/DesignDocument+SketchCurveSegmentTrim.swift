import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Removes the segment of a sketch line, arc, circle or open spline that holds the point nearest
    /// `point`, in the sketch's plane coordinates. Segments are bounded by the curve's ends, its
    /// crossings with every other curve of the sketch and a spline's span joints; the point only
    /// chooses the segment. Any refusal leaves the document unchanged.
    public mutating func trimSketchCurve(
        target: SelectionTarget,
        near point: Point2D,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws {
        let selection = try editableSketchEntity(for: target, operationName: "Trim")
        try validateSketchCurveHasNoBridgeUse(selection)
        let before = self
        do {
            if case .circle(let circle) = selection.entity {
                try trimSketchCircle(selection, circle: circle, near: point, objectRegistry: objectRegistry)
            } else {
                try trimOpenSketchCurve(selection, target: target, near: point, objectRegistry: objectRegistry)
            }
        } catch {
            self = before
            throw error
        }
    }

    /// Where a view ray through the pointer meets the plane of the sketch `target` names, as placed
    /// by the scene node presenting it, in that plane's coordinates. A ray along the plane or
    /// pointing away from it meets no point there and is refused.
    public func sketchPlanePoint(
        alongRay origin: Point3D,
        direction: Vector3D,
        on target: SelectionTarget
    ) throws -> Point2D {
        let selection = try editableSketchEntity(for: target, operationName: "Sketch plane point")
        let world = try SceneNodeHierarchy(metadata: productMetadata).worldTransform(of: target.sceneNodeID)
        let localOrigin = try world.inverse().applied(to: origin)
        let localDirection = try world.inverseApplyingLinearPart(to: direction)
            .normalized(tolerance: ModelingTolerance.standard.distance)
        let plane = try SketchPlaneCoordinateSystem(plane: selection.sketch.plane)
        let approach = localDirection.dot(plane.normal)
        // The viewport's own plane intersections refuse the same parallel rays.
        guard abs(approach) > 1e-12 else {
            throw EditorError(code: .commandInvalid, message: "The view looks along the sketch's plane; turn it to click on the curve.")
        }
        let distance = (plane.origin - localOrigin).dot(plane.normal) / approach
        guard distance >= 0 else {
            throw EditorError(code: .commandInvalid, message: "The sketch's plane lies behind the view.")
        }
        return plane.project(localOrigin + localDirection * distance).point
    }

    private mutating func trimOpenSketchCurve(
        _ selection: EditableSketchEntitySelection,
        target: SelectionTarget,
        near point: Point2D,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        var bounds = try trimCrossings(of: selection)
        if case .spline(let spline) = selection.entity {
            let spanCount = (spline.controlPoints.count - 1) / 3
            bounds += (1..<max(spanCount, 1)).map { Double($0) / Double(spanCount) }
        }
        bounds = uniqueInteriorCutFractions(bounds)
        let picked = try sketchCurveSplitParameter(of: selection.entity, nearestTo: point)
        let lower = bounds.last { $0 < picked } ?? 0
        let upper = bounds.first { $0 > picked } ?? 1
        let cuts = [lower, upper].filter { $0 > 0 && $0 < 1 }
        guard !cuts.isEmpty else {
            try removeSketchCurve(selection, objectRegistry: objectRegistry)
            return
        }
        // Sequential splits keep [0, first cut] on the original entity and hand each later piece
        // to a new one, in order.
        var pieces = [selection.entityID]
        var remaining = target
        for local in try sequentialCutCurveLocalFractions(fractions: cuts, entity: selection.entity) {
            let created = try splitSketchCurve(target: remaining, fraction: .scalar(local), objectRegistry: objectRegistry)
            pieces.append(created)
            remaining = SelectionTarget(
                sceneNodeID: target.sceneNodeID,
                component: .sketchEntity(.sketchEntity(featureID: selection.featureID, entityID: created))
            )
        }
        let removed = lower > 0 ? pieces[1] : pieces[0]
        let piece = try editableSketchEntity(
            for: SelectionTarget(
                sceneNodeID: target.sceneNodeID,
                component: .sketchEntity(.sketchEntity(featureID: selection.featureID, entityID: removed))
            ),
            operationName: "Trim"
        )
        try validateSketchCurveHasNoBridgeUse(piece)
        try removeSketchCurve(piece, objectRegistry: objectRegistry)
    }

    /// A circle keeps the arc from the next crossing after the picked point round to the one before
    /// it; with fewer than two crossings nothing bounds a segment, so the circle is removed.
    private mutating func trimSketchCircle(
        _ selection: EditableSketchEntitySelection,
        circle: SketchCircle,
        near point: Point2D,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let angles = try trimCrossings(of: selection)
        guard angles.count >= 2 else {
            try removeSketchCurve(selection, objectRegistry: objectRegistry)
            return
        }
        let picked = try sketchCurveSplitParameter(of: selection.entity, nearestTo: point)
        let offsets = angles.map { normalizedAngleDelta(from: picked, to: $0) }
        guard let nextIndex = offsets.indices.min(by: { offsets[$0] < offsets[$1] }),
              let previousIndex = offsets.indices.max(by: { offsets[$0] < offsets[$1] }) else {
            throw EditorError(code: .commandInvalid, message: "Trim found no crossing on the circle.")
        }
        let arc = SketchArc(
            center: circle.center,
            radius: circle.radius,
            startAngle: .angle(angles[nextIndex], .radian),
            endAngle: .angle(angles[previousIndex], .radian)
        )
        try validateArc(arc, owner: "Trim circle")
        try validateSketchCircleCanCut(selection: selection)
        var feature = selection.feature
        var sketch = selection.sketch
        sketch.entities[selection.entityID] = .arc(arc)
        if selection.sketch.entities.count == 1 {
            try markSketchObjectAsSourceEdited(featureID: selection.featureID)
        }
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: sketch,
            objectRegistry: objectRegistry,
            errorOwner: "Trim"
        )
    }
}
