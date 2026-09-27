import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Split Segment on a closed spline: the loop opens where `point` projects onto it and becomes
    /// an open spline that starts and ends there, one span longer when the point falls inside a
    /// span. References to its control points follow them around the loop; a reference to the two
    /// inner points of the span split at the point, or to the spline's ends, has no counterpart and
    /// refuses the split.
    mutating func openClosedSketchSpline(
        _ selection: EditableSketchEntitySelection,
        spline: SketchSpline,
        at point: Point2D,
        objectRegistry: ObjectTypeRegistry
    ) throws {
        let points = try spline.controlPoints.map { controlPoint -> Point2D in
            let resolved = try resolvedSketchPoint(controlPoint, owner: "Split Segment control point")
            return Point2D(x: resolved.x, y: resolved.y)
        }
        let spanCount = (points.count - 1) / 3
        guard spanCount >= 1, (points.count - 1).isMultiple(of: 3) else {
            throw EditorError(code: .commandInvalid, message: "Split Segment needs a spline of whole cubic spans.")
        }
        let parameter: Double
        do {
            parameter = try SketchCurveProjector(tolerance: .standard)
                .nearest(on: .cubicBezierChain(controlPoints: points), to: point).parameter
        } catch let error as KernelError {
            throw EditorError(code: .commandInvalid, message: "The curve point could not be found: \(error.message)")
        }
        var span = min(Int(parameter), spanCount - 1)
        var t = parameter - Double(span)
        let joint = t <= 1e-9 || t >= 1 - 1e-9
        if t >= 1 - 1e-9 { span = (span + 1) % spanCount; t = 0 }
        let n3 = 3 * spanCount
        let entityID = selection.entityID
        let sketch = selection.sketch
        let endsReferenced = sketch.constraints.contains { constraint in
            switch constraint {
            case .splineEndpointTangent(let tangency): tangency.splineEndpoint.splineID == entityID
            case .tangentSplineEndpoints(let pair), .smoothSplineEndpoints(let pair):
                pair.first.splineID == entityID || pair.second.splineID == entityID
            default: false
            }
        }
        guard !endsReferenced else {
            throw EditorError(code: .commandInvalid, message: "Split Segment cannot open a closed spline whose ends a constraint names.")
        }

        var opened: [SketchPoint]
        let newIndex: (Int) -> Int
        if joint {
            // The loop opens at joint `span`: the same points, starting there.
            let start = 3 * span
            opened = Array(spline.controlPoints[start...n3]) + Array(spline.controlPoints[1..<(start + 1)])
            newIndex = { index in ((index % n3) - start + n3) % n3 }
        } else {
            let lost = [3 * span + 1, 3 * span + 2]
            guard !lost.contains(where: { sketch.namesSplineControlPoint(entity: entityID, index: $0) }) else {
                throw EditorError(code: .commandInvalid, message: "Split Segment cannot keep a constraint on the split span's inner control points.")
            }
            let p = Array(points[(3 * span)...(3 * span + 3)])
            func lerp(_ a: Point2D, _ b: Point2D) -> Point2D { Point2D(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t) }
            let a = lerp(p[0], p[1]), b = lerp(p[1], p[2]), c = lerp(p[2], p[3])
            let d = lerp(a, b), e = lerp(b, c), middle = lerp(d, e)
            let after = 3 * span + 3
            opened = [middle, e, c].map { sketchPoint(x: $0.x, y: $0.y) }
                + Array(spline.controlPoints[after...n3])
                + Array(spline.controlPoints[1..<(3 * span + 1)])
                + [a, d, middle].map { sketchPoint(x: $0.x, y: $0.y) }
            newIndex = { index in (((index % n3) - after) % n3 + n3) % n3 + 3 }
        }
        var updatedSketch = sketch
        updatedSketch.remapSplineControlPoints(entity: entityID, newIndex)
        let openedSpline = SketchSpline(controlPoints: opened, isClosed: false)
        try validateSpline(openedSpline, owner: "Split Segment")
        updatedSketch.entities[entityID] = .spline(openedSpline)
        var feature = selection.feature
        try commitSketchEntityEdit(
            featureID: selection.featureID,
            feature: &feature,
            sketch: updatedSketch,
            objectRegistry: objectRegistry,
            errorOwner: "Split Segment"
        )
    }
}
