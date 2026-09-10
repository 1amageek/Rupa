import CoreGraphics
import Foundation

private enum ViewportSpatialInteractionInputMathSupport {
    static func invalid(_ message: String) -> MeshSourcePresentationRenderError {
        RealityViewportSpatialBatch.invalid(message)
    }

    static func validate(_ point: CGPoint, name: String) throws {
        guard point.x.isFinite, point.y.isFinite else {
            throw invalid("\(name) is not finite.")
        }
    }

    static func validate(_ vector: CGVector, name: String) throws {
        guard vector.dx.isFinite, vector.dy.isFinite else {
            throw invalid("\(name) is not finite.")
        }
    }

    static func length(_ vector: CGVector) -> CGFloat {
        hypot(vector.dx, vector.dy)
    }

    static func validateDirection(_ vector: CGVector, name: String) throws {
        try validate(vector, name: name)
        let value = length(vector)
        guard value.isFinite, value > 1.0e-9 else {
            throw invalid("\(name) is degenerate.")
        }
    }

    static func normalizedSignedAngle(_ value: Double, minimum: Double) throws -> Double {
        guard value.isFinite, minimum.isFinite, minimum > 0.0 else {
            throw invalid("Angle input is invalid.")
        }
        guard abs(value) >= minimum else {
            return value < 0.0 ? -minimum : minimum
        }
        return value
    }

    static func normalizedAngleDelta(from start: Double, to end: Double) throws -> Double {
        guard start.isFinite, end.isFinite else {
            throw invalid("Projected angle is not finite.")
        }
        var delta = end - start
        guard delta.isFinite else {
            throw invalid("Projected angle delta is not finite.")
        }
        while delta <= -.pi {
            delta += .pi * 2.0
        }
        while delta > .pi {
            delta -= .pi * 2.0
        }
        guard delta.isFinite else {
            throw invalid("Projected angle delta is not finite.")
        }
        return delta
    }

    /// The signed parameter of `point` on the projected radial basis.
    ///
    /// `nil` means the point carries no direction because it sits on the
    /// projected centre, which leaves the caller's retained value unchanged. A
    /// collinear basis is refused instead: the drag cannot recover a CAD angle
    /// from it, and answering with a screen-polar angle would report a rotation
    /// the drawn arc never had.
    static func projectedAngleParameter(
        center: CGPoint,
        radial: CGVector,
        tangent: CGVector,
        point: CGPoint
    ) throws -> Double? {
        try validate(center, name: "Projected center")
        try validate(radial, name: "Projected radial vector")
        try validate(tangent, name: "Projected tangent vector")
        try validate(point, name: "Input point")

        let delta = CGVector(dx: point.x - center.x, dy: point.y - center.y)
        try validate(delta, name: "Projected point delta")
        guard length(delta) > 1.0e-9 else {
            return nil
        }

        let determinant = radial.dx * tangent.dy - radial.dy * tangent.dx
        guard determinant.isFinite else {
            throw invalid("Projected radial basis is not finite.")
        }
        let determinantScale = max(length(radial) * length(tangent), 1.0)
        guard determinantScale.isFinite else {
            throw invalid("Projected radial basis scale is not finite.")
        }

        guard abs(determinant) > determinantScale * 1.0e-9 else {
            throw invalid("Projected radial basis is collinear.")
        }
        let cosine = (delta.dx * tangent.dy - delta.dy * tangent.dx) / determinant
        let sine = (radial.dx * delta.dy - radial.dy * delta.dx) / determinant
        let magnitude = hypot(cosine, sine)
        guard cosine.isFinite, sine.isFinite, magnitude.isFinite, magnitude > 1.0e-9 else {
            return nil
        }
        return atan2(sine, cosine)
    }

    static func roundedInteger(_ value: Double, name: String) throws -> Int {
        guard value.isFinite else {
            throw invalid("\(name) is not finite.")
        }
        let rounded = value.rounded()
        let upperExclusive = -Double(Int.min)
        guard rounded.isFinite,
              rounded >= Double(Int.min),
              rounded < upperExclusive else {
            throw invalid("\(name) overflows Int.")
        }
        return Int(rounded)
    }

    static func addCount(_ base: Int, delta: Int) throws -> Int {
        guard base > 0 else {
            throw invalid("Base copy count is not positive.")
        }
        let (value, overflow) = base.addingReportingOverflow(delta)
        guard !overflow else {
            throw invalid("Copy count overflows Int.")
        }
        return max(value, 1)
    }

    static func countDelta(
        start: CGPoint,
        current: CGPoint,
        direction: CGVector,
        pointsPerCopy: CGFloat
    ) throws -> Int {
        try validate(start, name: "Drag start")
        try validate(current, name: "Drag current")
        try validateDirection(direction, name: "Projected copy direction")
        guard pointsPerCopy.isFinite, pointsPerCopy > 0.0 else {
            throw invalid("Points per copy is invalid.")
        }
        let delta = CGVector(dx: current.x - start.x, dy: current.y - start.y)
        try validate(delta, name: "Drag delta")
        let projected = delta.dx * direction.dx + delta.dy * direction.dy
        guard projected.isFinite else {
            throw invalid("Projected drag distance is not finite.")
        }
        let ratio = Double(projected) / Double(pointsPerCopy)
        return try roundedInteger(ratio, name: "Copy-count delta")
    }

    static func curveDistance(
        current: CGPoint,
        projectedPathPoints: [CGPoint],
        distanceSamplesMeters: [Double],
        baseDistanceMeters: Double,
        totalLengthMeters: Double,
        minimumDistanceMeters: Double
    ) throws -> Double {
        try validate(current, name: "Curve drag point")
        guard projectedPathPoints.count >= 2,
              projectedPathPoints.count == distanceSamplesMeters.count,
              baseDistanceMeters.isFinite,
              totalLengthMeters.isFinite,
              totalLengthMeters > 0.0,
              minimumDistanceMeters.isFinite,
              minimumDistanceMeters > 0.0 else {
            throw invalid("Curve extent projection is invalid.")
        }

        var previousDistance = distanceSamplesMeters[0]
        guard previousDistance.isFinite else {
            throw invalid("Curve distance samples are not finite.")
        }
        for point in projectedPathPoints {
            try validate(point, name: "Curve projected point")
        }
        guard previousDistance >= 0.0, previousDistance <= totalLengthMeters else {
            throw invalid("Curve distance sample is outside the path.")
        }

        var bestDistance = previousDistance
        var bestScreenDistance = CGFloat.infinity
        var hasProjectedSegment = false
        for index in 1 ..< projectedPathPoints.count {
            let nextDistance = distanceSamplesMeters[index]
            guard nextDistance.isFinite,
                  nextDistance > previousDistance,
                  nextDistance <= totalLengthMeters else {
                throw invalid("Curve distance samples are not increasing.")
            }

            let start = projectedPathPoints[index - 1]
            let end = projectedPathPoints[index]
            let dx = end.x - start.x
            let dy = end.y - start.y
            let lengthSquared = dx * dx + dy * dy
            guard lengthSquared.isFinite else {
                throw invalid("Curve projected segment is not finite.")
            }

            let t: CGFloat
            if lengthSquared > 1.0e-12 {
                hasProjectedSegment = true
                let raw = ((current.x - start.x) * dx + (current.y - start.y) * dy) / lengthSquared
                guard raw.isFinite else {
                    throw invalid("Curve nearest-point parameter is not finite.")
                }
                t = min(max(raw, 0.0), 1.0)
            } else {
                t = 0.0
            }
            let projected = CGPoint(x: start.x + dx * t, y: start.y + dy * t)
            let screenDistance = hypot(current.x - projected.x, current.y - projected.y)
            guard screenDistance.isFinite else {
                throw invalid("Curve screen distance is not finite.")
            }
            if screenDistance < bestScreenDistance {
                let distance = previousDistance + (nextDistance - previousDistance) * Double(t)
                guard distance.isFinite else {
                    throw invalid("Curve physical distance is not finite.")
                }
                bestDistance = distance
                bestScreenDistance = screenDistance
            }
            previousDistance = nextDistance
        }

        guard hasProjectedSegment, bestDistance.isFinite else {
            throw invalid("Curve projection has no resolvable physical distance.")
        }
        return min(max(bestDistance, minimumDistanceMeters), totalLengthMeters)
    }
}

extension ViewportSpatialMaterializedInteractionTarget.RadialProjection {
    /// The rotated angle for this update, or `nil` when the pointer sits on the
    /// projected centre and carries no direction to rotate towards.
    func angle(start: CGPoint, current: CGPoint) throws -> Double? {
        guard baseAngleRadians.isFinite,
              minimumAngleRadians.isFinite,
              minimumAngleRadians > 0.0 else {
            throw ViewportSpatialInteractionInputMathSupport.invalid("Radial projection is invalid.")
        }
        guard let startParameter = try ViewportSpatialInteractionInputMathSupport.projectedAngleParameter(
            center: center,
            radial: radialVector,
            tangent: tangentVector,
            point: start
        ), let currentParameter = try ViewportSpatialInteractionInputMathSupport.projectedAngleParameter(
            center: center,
            radial: radialVector,
            tangent: tangentVector,
            point: current
        ) else {
            return nil
        }
        let delta = try ViewportSpatialInteractionInputMathSupport.normalizedAngleDelta(
            from: startParameter,
            to: currentParameter
        )
        let value = baseAngleRadians + delta
        guard value.isFinite else {
            throw ViewportSpatialInteractionInputMathSupport.invalid("Radial angle overflows.")
        }
        return try ViewportSpatialInteractionInputMathSupport.normalizedSignedAngle(
            value,
            minimum: minimumAngleRadians
        )
    }
}

extension ViewportSpatialMaterializedInteractionTarget.LinearCopyCountProjection {
    func count(start: CGPoint, current: CGPoint) throws -> Int {
        let delta = try ViewportSpatialInteractionInputMathSupport.countDelta(
            start: start,
            current: current,
            direction: projectedDirection,
            pointsPerCopy: pointsPerCopy
        )
        return try ViewportSpatialInteractionInputMathSupport.addCount(baseCopyCount, delta: delta)
    }
}

extension ViewportSpatialMaterializedInteractionTarget.LinearDensityProjection {
    func count(start: CGPoint, current: CGPoint) throws -> Int {
        let delta = try ViewportSpatialInteractionInputMathSupport.countDelta(
            start: start,
            current: current,
            direction: projectedDirection,
            pointsPerCopy: pointsPerCopy
        )
        return try ViewportSpatialInteractionInputMathSupport.addCount(baseCopyCount, delta: delta)
    }
}

extension ViewportSpatialMaterializedInteractionTarget.AngularCopyCountProjection {
    /// The stepped copy count for this update, or `nil` when the pointer sits on
    /// the projected centre and carries no direction to step along.
    func count(start: CGPoint, current: CGPoint) throws -> Int? {
        guard stepAngleRadians.isFinite, abs(stepAngleRadians) > 1.0e-12,
              baseCopyCount > 0, minimumAngleRadians.isFinite, minimumAngleRadians > 0.0 else {
            throw ViewportSpatialInteractionInputMathSupport.invalid("Angular copy-count projection is invalid.")
        }
        guard let startParameter = try ViewportSpatialInteractionInputMathSupport.projectedAngleParameter(
            center: center,
            radial: radialVector,
            tangent: tangentVector,
            point: start
        ), let currentParameter = try ViewportSpatialInteractionInputMathSupport.projectedAngleParameter(
            center: center,
            radial: radialVector,
            tangent: tangentVector,
            point: current
        ) else {
            return nil
        }
        let deltaAngle = try ViewportSpatialInteractionInputMathSupport.normalizedAngleDelta(
            from: startParameter,
            to: currentParameter
        )
        let delta = try ViewportSpatialInteractionInputMathSupport.roundedInteger(
            deltaAngle / stepAngleRadians,
            name: "Angular copy-count delta"
        )
        return try ViewportSpatialInteractionInputMathSupport.addCount(baseCopyCount, delta: delta)
    }
}

extension ViewportSpatialMaterializedInteractionTarget.AngularDensityProjection {
    func count(start: CGPoint, current: CGPoint) throws -> Int {
        let delta = try ViewportSpatialInteractionInputMathSupport.countDelta(
            start: start,
            current: current,
            direction: projectedDirection,
            pointsPerCopy: pointsPerCopy
        )
        return try ViewportSpatialInteractionInputMathSupport.addCount(baseCopyCount, delta: delta)
    }
}

extension ViewportSpatialMaterializedInteractionTarget.CurveCopyCountProjection {
    func count(start: CGPoint, current: CGPoint) throws -> Int {
        let delta = try ViewportSpatialInteractionInputMathSupport.countDelta(
            start: start,
            current: current,
            direction: projectedDirection,
            pointsPerCopy: pointsPerCopy
        )
        return try ViewportSpatialInteractionInputMathSupport.addCount(baseCopyCount, delta: delta)
    }
}

extension ViewportSpatialMaterializedInteractionTarget.CurveExtentProjection {
    func distance(current: CGPoint) throws -> Double {
        try ViewportSpatialInteractionInputMathSupport.curveDistance(
            current: current,
            projectedPathPoints: projectedPathPoints,
            distanceSamplesMeters: distanceSamplesMeters,
            baseDistanceMeters: baseDistanceMeters,
            totalLengthMeters: totalLengthMeters,
            minimumDistanceMeters: minimumDistanceMeters
        )
    }
}
