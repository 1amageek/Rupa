import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    /// The Bridge Curve between two resolved curve ends, from Swift-CAD's bridge solver: one
    /// Bezier of degree k₁ + k₂ + 1 for the end continuities, leaving the first end along its
    /// outgoing tangent and arriving at the second against its outgoing tangent, with each end's
    /// three tensions (the first scales the end speed from the chord length). It is a sketch
    /// spline in chain form of that degree with one span.
    func bridgeSpline(
        first: SketchCurveEndpointSample,
        second: SketchCurveEndpointSample,
        continuity: BridgeCurveContinuity,
        firstTension: BridgeCurveTension,
        secondTension: BridgeCurveTension,
        sketch: Sketch
    ) throws -> SketchSpline {
        let firstTensions = try resolvedBridgeTensions(firstTension, owner: "Bridge curve first tension")
        let secondTensions = try resolvedBridgeTensions(secondTension, owner: "Bridge curve second tension")
        let chordLength = hypot(
            second.sample.point.x - first.sample.point.x,
            second.sample.point.y - first.sample.point.y
        )
        let start = CurveBridgeEndpointConstraint(
            target: try bridgeContinuityTarget(first, direction: first.outgoingTangent, sketch: sketch),
            requiredLevel: curveContinuityLevel(continuity.first),
            derivativeMagnitude: continuity.first == .g0 ? nil : firstTensions.first * chordLength,
            secondTension: firstTensions.second,
            thirdTension: firstTensions.third
        )
        let arrival = CADCore.Point2D(x: -second.outgoingTangent.x, y: -second.outgoingTangent.y)
        let end = CurveBridgeEndpointConstraint(
            target: try bridgeContinuityTarget(second, direction: arrival, sketch: sketch),
            requiredLevel: curveContinuityLevel(continuity.second),
            derivativeMagnitude: continuity.second == .g0 ? nil : secondTensions.first * chordLength,
            secondTension: secondTensions.second,
            thirdTension: secondTensions.third
        )
        let result: CurveBridgeResult
        do {
            result = try CurveBridgeSolver(modelingTolerance: .standard).solve(CurveBridgeRequest(
                start: start,
                end: end,
                continuityTolerances: .standard(modelingTolerance: .standard)
            ))
        } catch let error as KernelError {
            throw EditorError(code: .commandInvalid, message: "Bridge curve: \(error.message)")
        }
        return SketchSpline(
            controlPoints: result.curve.controlPoints.map { sketchPoint(x: $0.x, y: $0.y) },
            degree: result.curve.degree
        )
    }

    /// The source curve at a bridge end as exact geometry in the sketch plane (z = 0), at the
    /// sample's parameter, oriented so its tangent points along `direction`: a line on its
    /// arc length, an arc's circle on its angle and a spline on its own knots.
    private func bridgeContinuityTarget(
        _ sample: SketchCurveEndpointSample,
        direction: CADCore.Point2D,
        sketch: Sketch
    ) throws -> CurveContinuityTarget {
        guard let entity = sketch.entities[sample.entityID] else {
            throw EditorError(code: .referenceUnresolved, message: "Bridge curve source curve could not be resolved.")
        }
        let fraction = sample.sample.parameter
        let curve: Curve3D
        let parameter: Double
        switch entity {
        case .line(let line):
            let start = try resolvedSketchPoint(line.start, owner: "Bridge curve source line start")
            let end = try resolvedSketchPoint(line.end, owner: "Bridge curve source line end")
            // A line's direction is a unit vector and its parameter the distance from the origin.
            let length = hypot(end.x - start.x, end.y - start.y)
            guard length > 0 else {
                throw EditorError(code: .commandInvalid, message: "Bridge curve source line must not be degenerate.")
            }
            curve = .line(Line3D(
                origin: Point3D(x: start.x, y: start.y, z: 0),
                direction: Vector3D(x: (end.x - start.x) / length, y: (end.y - start.y) / length, z: 0)
            ))
            parameter = fraction * length
        case .arc(let arc):
            let center = try resolvedSketchPoint(arc.center, owner: "Bridge curve source arc center")
            let radius = try resolvedPositiveLengthValue(arc.radius, owner: "Bridge curve source arc radius")
            let startAngle = try resolvedAngleValue(arc.startAngle, owner: "Bridge curve source arc start")
            let endAngle = try resolvedAngleValue(arc.endAngle, owner: "Bridge curve source arc end")
            curve = .circle(Circle3D(center: Point3D(x: center.x, y: center.y, z: 0), normal: .unitZ, radius: radius))
            parameter = startAngle + fraction * positiveArcSpan(startAngle: startAngle, endAngle: endAngle)
        case .spline(let spline):
            let planar = try resolvedSketchSplineCurve(spline, owner: "Bridge curve source spline")
            curve = .bSpline(BSplineCurve3D(
                degree: planar.degree,
                knots: planar.bSpline.knots,
                controlPoints: planar.bSpline.controlPoints.map { Point3D(x: $0.x, y: $0.y, z: 0) }
            ))
            parameter = planar.parameter(ofFraction: fraction)
        case .point, .circle:
            throw EditorError(code: .commandInvalid, message: "Bridge curve ends must lie on a line, arc or spline.")
        }
        let tangent = sample.sample.tangent
        let alongParameter = tangent.x * direction.x + tangent.y * direction.y >= 0
        return CurveContinuityTarget(curve: curve, parameter: parameter, orientation: alongParameter ? .forward : .reversed)
    }

    private func curveContinuityLevel(_ continuity: BridgeCurveEndpointContinuity) -> CurveContinuityLevel {
        switch continuity {
        case .g0: .positional
        case .g1: .tangent
        case .g2: .curvature
        case .g3: .curvatureVariation
        }
    }

    private func resolvedBridgeTensions(
        _ tension: BridgeCurveTension,
        owner: String
    ) throws -> (first: Double, second: Double, third: Double) {
        (
            try resolvedPositiveScalarValue(tension.first, owner: "\(owner) 1"),
            try resolvedPositiveScalarValue(tension.second, owner: "\(owner) 2"),
            try resolvedPositiveScalarValue(tension.third, owner: "\(owner) 3")
        )
    }

    /// A Bridge Curve end's declared continuity and the continuity Swift-CAD measures between the
    /// source and the bridge's own curve there.
    struct BridgeEndContinuity: Sendable {
        var bridgeReference: SketchReference
        var sourceReference: SketchReference
        var required: BridgeCurveEndpointContinuity
        var achieved: CurveContinuityLevel?
        var positionGap: Double
        var tangentAngle: Double
        var curvatureGap: Double
    }

    /// The continuity at each point-referenced end of the bridge `source` builds: required as the
    /// source declares it, achieved as `CurveContinuityEvaluator` measures it on the exact source
    /// curve and the stored bridge, G3 included.
    func bridgeEndContinuities(source: BridgeCurveSource, sketch: Sketch) throws -> [BridgeEndContinuity] {
        guard case .spline(let bridge) = sketch.entities[source.entityID] else {
            throw EditorError(code: .referenceUnresolved, message: "Bridge curve source must point to a generated spline.")
        }
        let resolver = SketchCurveEndpointResolver()
        guard let first = try resolver.sample(for: source.firstEndpoint, sketch: sketch, document: self),
              let second = try resolver.sample(for: source.secondEndpoint, sketch: sketch, document: self) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Bridge curve endpoints must resolve to line, arc, or spline curve positions."
            )
        }
        let planar = try resolvedSketchSplineCurve(bridge, owner: "Bridge curve")
        let knots = planar.bSpline.knots
        let curve = Curve3D.bSpline(BSplineCurve3D(
            degree: planar.degree,
            knots: knots,
            controlPoints: planar.bSpline.controlPoints.map { Point3D(x: $0.x, y: $0.y, z: 0) }
        ))
        let arrival = CADCore.Point2D(x: -second.outgoingTangent.x, y: -second.outgoingTangent.y)
        let ends: [(sample: SketchCurveEndpointSample, direction: CADCore.Point2D, continuity: BridgeCurveEndpointContinuity, parameter: Double, index: Int)] = [
            (first, first.outgoingTangent, source.continuity.first, knots[0], 0),
            (second, arrival, source.continuity.second, knots[knots.count - 1], bridge.controlPoints.count - 1),
        ]
        let evaluator = CurveContinuityEvaluator(modelingTolerance: .standard)
        return try ends.compactMap { end in
            guard let sourceReference = end.sample.pointReference else {
                return nil
            }
            let result: CurveContinuityResult
            do {
                result = try evaluator.evaluate(CurveContinuityRequest(
                    first: try bridgeContinuityTarget(end.sample, direction: end.direction, sketch: sketch),
                    second: CurveContinuityTarget(curve: curve, parameter: end.parameter),
                    requiredLevel: curveContinuityLevel(end.continuity),
                    tolerances: .standard(modelingTolerance: .standard)
                ))
            } catch let error as KernelError {
                throw EditorError(code: .evaluationFailed, message: "Bridge curve continuity: \(error.message)")
            }
            return BridgeEndContinuity(
                bridgeReference: .splineControlPoint(entity: source.entityID, index: end.index),
                sourceReference: sourceReference,
                required: end.continuity,
                achieved: result.achievedLevel,
                positionGap: result.deviation.positionDistance,
                tangentAngle: result.deviation.tangentAngle,
                curvatureGap: result.deviation.curvatureVectorDistance
            )
        }
    }
}
