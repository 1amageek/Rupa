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
        // Both curves in world space, through their sketches' placed planes.
        let firstSystem = try placedSketchSystem(for: first, plane: a.sketch.plane)
        let secondSystem = try placedSketchSystem(for: second, plane: b.sketch.plane)
        let trace: PlanarCurveExtrusionIntersector.Trace
        do {
            trace = try PlanarCurveExtrusionIntersector(tolerance: tolerance).trace(
                first: try planarFrameCurve(a.entity, system: firstSystem, owner: owner),
                second: try planarFrameCurve(b.entity, system: secondSystem, owner: owner)
            )
        } catch let error as KernelError {
            throw EditorError(code: .commandInvalid, message: "\(owner): \(error.message)")
        }
        let breakpoints = try spatialSourceCurve(a.entity, system: firstSystem, owner: owner).breakpoints
        let fitted = try SpatialCurveFitter(deviation: tolerance.distance * Self.spatialFitDeviationFactor).fit(
            breakpoints: breakpoints, isClosed: false, tolerance: tolerance, point: trace.point(at:)
        )
        return try createWorldSpatialPath(
            name: "\(a.feature.name ?? "Curve") \(b.feature.name ?? "Curve") Projection",
            path: fitted.path, objectRegistry: objectRegistry
        )
    }

    /// A sketch curve over the same parameter `spatialSourceCurve` uses, with its first
    /// derivative, in an orthonormal frame of its placed plane: a placement may scale or shear
    /// the sketch's own axes, so its points and derivatives are carried through them into the
    /// world and read back along orthonormal axes of the same plane.
    private func planarFrameCurve(_ entity: SketchEntity, system: SketchPlaneCoordinateSystem, owner: String) throws -> PlanarFrameCurve {
        let tolerance = modelingSettings.tolerance.distance
        let axisU = try system.u.normalized(tolerance: tolerance)
        let axisV = try system.normal.cross(axisU).normalized(tolerance: tolerance)
        let placedU = system.u, placedV = system.v
        func frame(
            _ lower: Double, _ upper: Double,
            _ point: @escaping @Sendable (Double) throws -> Point2D,
            _ derivative: @escaping @Sendable (Double) throws -> Point2D
        ) -> PlanarFrameCurve {
            PlanarFrameCurve(
                origin: system.origin, u: axisU, v: axisV, normal: system.normal, lower: lower, upper: upper,
                point: { w in
                    let local = try point(w)
                    let offset = placedU * local.x + placedV * local.y
                    return Point2D(x: offset.dot(axisU), y: offset.dot(axisV))
                },
                derivative: { w in
                    let local = try derivative(w)
                    let offset = placedU * local.x + placedV * local.y
                    return Point2D(x: offset.dot(axisU), y: offset.dot(axisV))
                }
            )
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
