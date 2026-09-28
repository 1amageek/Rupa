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

    /// Rebuilds every Bridge Curve of `featureID` from its sources' current geometry and
    /// tensions, so a bridge keeps its continuity at every level whatever edit moved its sources.
    /// The constraints the bridge owns are rewritten with it, since their last control point
    /// index follows the regenerated degree. A bridge whose ends no longer resolve, or that its
    /// sources can no longer take, fails the edit.
    func regenerateBridgeCurves(featureID: FeatureID, sketch: inout Sketch) throws {
        let resolver = SketchCurveEndpointResolver()
        let sources = productMetadata.bridgeCurveSources.values
            .filter { $0.featureID == featureID }
            .sorted { $0.id.description < $1.id.description }
        for source in sources {
            guard case .spline(let previous) = sketch.entities[source.entityID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Bridge curve source must point to a generated spline."
                )
            }
            guard let first = try resolver.sample(for: source.firstEndpoint, sketch: sketch, document: self),
                  let second = try resolver.sample(for: source.secondEndpoint, sketch: sketch, document: self) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Bridge curve endpoints must resolve to line, arc, or spline curve positions."
                )
            }
            let spline = try bridgeSpline(
                first: first,
                second: second,
                continuity: source.continuity,
                firstTension: source.firstEndpoint.tension,
                secondTension: source.secondEndpoint.tension,
                sketch: sketch
            )
            try validateSplineForm(spline, owner: "Bridge curve")
            let previousConstraints = bridgeOwnedConstraints(
                bridgeID: source.entityID,
                lastControlPointIndex: previous.controlPoints.count - 1,
                firstSample: first,
                secondSample: second,
                continuity: source.continuity
            )
            sketch.constraints.removeAll { previousConstraints.contains($0) }
            sketch.entities[source.entityID] = .spline(spline)
            for constraint in bridgeOwnedConstraints(
                bridgeID: source.entityID,
                lastControlPointIndex: spline.controlPoints.count - 1,
                firstSample: first,
                secondSample: second,
                continuity: source.continuity
            ) {
                appendBridgeConstraint(constraint, to: &sketch)
            }
        }
    }

    /// Rebuilds the Bridge Curves of every sketch after a change outside any one sketch (a
    /// document parameter can move a source or set a tension), replacing only the sketches whose
    /// bridges changed.
    mutating func regenerateAllBridgeCurves() throws {
        let featureIDs = Set(productMetadata.bridgeCurveSources.values.map(\.featureID))
            .sorted { $0.description < $1.description }
        guard featureIDs.isEmpty == false else {
            return
        }
        var updatedCADDocument = cadDocument
        for featureID in featureIDs {
            guard var feature = updatedCADDocument.designGraph.nodes[featureID],
                  case .sketch(let sketch) = feature.operation else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Bridge curve sources must point to existing sketch features."
                )
            }
            var regenerated = sketch
            try regenerateBridgeCurves(featureID: featureID, sketch: &regenerated)
            guard regenerated != sketch else {
                continue
            }
            feature.operation = .sketch(regenerated)
            do {
                try updatedCADDocument.replaceFeature(feature, tolerance: modelingSettings.tolerance)
            } catch {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Bridge curve regeneration produced invalid sketch geometry: \(error)."
                )
            }
        }
        cadDocument = updatedCADDocument
    }

    /// A Bridge Curve is derived from its sources: an edit of its control points would be undone
    /// by the next regeneration, so it is refused and the bridge is shaped by its parameters.
    func validateNotGeneratedBridgeCurve(featureID: FeatureID, entityID: SketchEntityID, operationName: String) throws {
        guard productMetadata.bridgeCurveSources.values.contains(where: {
            $0.featureID == featureID && $0.entityID == entityID
        }) == false else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) cannot edit a generated Bridge Curve; change its tensions or continuity instead."
            )
        }
    }
}
