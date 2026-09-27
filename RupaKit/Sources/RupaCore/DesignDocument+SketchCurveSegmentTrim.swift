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

    /// The point of the sketch plane under the world point `point`, for the sketch `target` names
    /// through the scene node presenting it.
    public func sketchPlanePoint(ofWorld point: Point3D, on target: SelectionTarget) throws -> Point2D {
        let selection = try editableSketchEntity(for: target, operationName: "Sketch plane point")
        let world = try SceneNodeHierarchy(metadata: productMetadata).worldTransform(of: target.sceneNodeID)
        let local = try world.inverse().applied(to: point)
        return try SketchPlaneCoordinateSystem(plane: selection.sketch.plane).project(local).point
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
        let picked = try trimPickedParameter(of: selection.entity, near: point)
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
        let center = Point2D(
            x: try resolvedLengthValue(circle.center.x, owner: "Trim circle center x"),
            y: try resolvedLengthValue(circle.center.y, owner: "Trim circle center y")
        )
        let picked = atan2(point.y - center.y, point.x - center.x)
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

    /// The parameter of the curve sample nearest `point`: fraction for a line or arc, the chain
    /// parameter over span count for a spline. It chooses a segment and never a cut position.
    private func trimPickedParameter(of entity: SketchEntity, near point: Point2D) throws -> Double {
        let sampler = SketchCurveSampler(samplesPerSegment: 256)
        func resolved(_ source: SketchPoint, _ owner: String) throws -> Point2D {
            Point2D(
                x: try resolvedLengthValue(source.x, owner: "\(owner) x"),
                y: try resolvedLengthValue(source.y, owner: "\(owner) y")
            )
        }
        let samples: [CurveEvaluationSample]
        switch entity {
        case .line(let line):
            let start = try resolved(line.start, "Trim line start")
            let end = try resolved(line.end, "Trim line end")
            let dx = end.x - start.x, dy = end.y - start.y
            let lengthSquared = dx * dx + dy * dy
            guard lengthSquared > 0 else {
                throw EditorError(code: .commandInvalid, message: "Trim found a line with no length.")
            }
            return min(max(((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared, 0), 1)
        case .arc(let arc):
            samples = sampler.arcSamples(
                center: try resolved(arc.center, "Trim arc center"),
                radius: try resolvedPositiveLengthValue(arc.radius, owner: "Trim arc radius"),
                startAngle: try resolvedAngleValue(arc.startAngle, owner: "Trim arc start angle"),
                endAngle: try resolvedAngleValue(arc.endAngle, owner: "Trim arc end angle")
            )
        case .spline(let spline):
            samples = sampler.splineSamples(for: try spline.controlPoints.map { try resolved($0, "Trim spline") })
        case .circle, .point:
            throw EditorError(code: .commandInvalid, message: "Trim takes a line, arc, circle or open spline.")
        }
        guard let nearest = samples.min(by: {
            hypot($0.point.x - point.x, $0.point.y - point.y) < hypot($1.point.x - point.x, $1.point.y - point.y)
        }) else {
            throw EditorError(code: .commandInvalid, message: "Trim could not sample the curve.")
        }
        return nearest.parameter
    }
}
