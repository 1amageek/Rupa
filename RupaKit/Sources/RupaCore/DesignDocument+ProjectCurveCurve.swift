import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// Project Curve Curve: the curve where two selected sketch curves' extrusions meet, each
    /// extruded along its own sketch plane's normal (Swift-CAD's `PlanarCurveExtrusionIntersector`
    /// over the first curve), fitted within ten modeling distances as one spatial path, in one
    /// step. Curves on parallel planes, or whose extrusions part partway, are refused.
    @discardableResult
    public mutating func projectCurveIntersection(
        first: SelectionTarget,
        second: SelectionTarget,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> FeatureID {
        let owner = "Project Curve Curve"
        let tolerance = modelingSettings.tolerance
        let a = try editableSketchEntity(for: first, operationName: owner)
        let b = try editableSketchEntity(for: second, operationName: owner)
        guard a.featureID != b.featureID || a.entityID != b.entityID else {
            throw EditorError(code: .commandInvalid, message: "\(owner) takes two different curves.")
        }
        let firstCurve = try planarFrameCurve(a.entity, plane: a.sketch.plane, owner: owner)
        let trace: PlanarCurveExtrusionIntersector.Trace
        do {
            trace = try PlanarCurveExtrusionIntersector(tolerance: tolerance).trace(
                first: firstCurve, second: try planarFrameCurve(b.entity, plane: b.sketch.plane, owner: owner)
            )
        } catch let error as KernelError {
            throw EditorError(code: .commandInvalid, message: "\(owner): \(error.message)")
        }
        let breakpoints = try spatialSourceCurve(a.entity, plane: a.sketch.plane, owner: owner).breakpoints
        let fitted = try SpatialCurveFitter(deviation: tolerance.distance * Self.spatialFitDeviationFactor).fit(
            breakpoints: breakpoints, isClosed: false, tolerance: tolerance, point: trace.point(at:)
        )
        return try createSpatialPath(
            name: "\(a.feature.name ?? "Curve") \(b.feature.name ?? "Curve") Projection",
            path: fitted.path, objectRegistry: objectRegistry
        )
    }

    /// A sketch curve in its plane's frame, over the same parameter `spatialSourceCurve` uses,
    /// with its first derivative.
    private func planarFrameCurve(_ entity: SketchEntity, plane: SketchPlane, owner: String) throws -> PlanarFrameCurve {
        let system = try SketchPlaneCoordinateSystem(plane: plane)
        func frame(
            _ lower: Double, _ upper: Double,
            _ point: @escaping @Sendable (Double) throws -> Point2D,
            _ derivative: @escaping @Sendable (Double) throws -> Point2D
        ) -> PlanarFrameCurve {
            PlanarFrameCurve(origin: system.origin, u: system.u, v: system.v, normal: system.normal,
                             lower: lower, upper: upper, point: point, derivative: derivative)
        }
        switch entity {
        case .line(let line):
            let start = try resolvedProjectionPoint(line.start, owner: "\(owner) line start")
            let end = try resolvedProjectionPoint(line.end, owner: "\(owner) line end")
            let delta = Point2D(x: end.x - start.x, y: end.y - start.y)
            return frame(0, 1, { w in Point2D(x: start.x + delta.x * w, y: start.y + delta.y * w) }, { _ in delta })
        case .arc(let arc):
            let center = try resolvedProjectionPoint(arc.center, owner: "\(owner) arc center")
            let radius = try resolvedPositiveLengthValue(arc.radius, owner: "\(owner) arc radius")
            let startAngle = try resolvedAngleValue(arc.startAngle, owner: "\(owner) arc start angle")
            let span = try normalizedPartialArcSpan(
                startAngle: startAngle, endAngle: try resolvedAngleValue(arc.endAngle, owner: "\(owner) arc end angle")
            )
            return frame(0, 1, { w in
                let angle = startAngle + span * w
                return Point2D(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            }, { w in
                let angle = startAngle + span * w
                return Point2D(x: -sin(angle) * radius * span, y: cos(angle) * radius * span)
            })
        case .circle(let circle):
            let center = try resolvedProjectionPoint(circle.center, owner: "\(owner) circle center")
            let radius = try resolvedPositiveLengthValue(circle.radius, owner: "\(owner) circle radius")
            let turn = 2 * Double.pi
            return frame(0, 1, { w in
                Point2D(x: center.x + cos(turn * w) * radius, y: center.y + sin(turn * w) * radius)
            }, { w in
                Point2D(x: -sin(turn * w) * radius * turn, y: cos(turn * w) * radius * turn)
            })
        case .spline(let spline):
            let curve = try resolvedSketchSplineCurve(spline, owner: owner).bSpline
            return frame(curve.knots[curve.degree], curve.knots[curve.knots.count - curve.degree - 1], { w in
                try curve.point(at: w, tolerance: .standard)
            }, { w in
                let d = try curve.differentialGeometry(at: w, tolerance: .standard).firstDerivative
                return Point2D(x: d.x, y: d.y)
            })
        case .point:
            throw EditorError(code: .commandInvalid, message: "\(owner) projects curves, not points.")
        }
    }
}
