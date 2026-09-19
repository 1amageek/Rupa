import CoreGraphics
import Foundation
import RupaCore
import RupaViewportScene

/// The closed input consumed by the MainActor input owner after a native
/// projection has been matched to the prepared interaction record.
///
/// This value intentionally contains no projection closure, layout, camera,
/// native entity, or source traversal result.  Projection-free routes retain
/// their checked semantic value.  Routes whose legacy drag math used screen
/// geometry retain only the finite projected samples and semantic scalars
/// needed by that math.
enum ViewportSpatialMaterializedInteractionTarget: Sendable {
    struct RadialProjection: Sendable {
        let center: CGPoint
        let radialVector: CGVector
        let tangentVector: CGVector
        let baseAngleRadians: Double
        let minimumAngleRadians: Double
    }

    struct LinearCopyCountProjection: Sendable {
        let basePoint: CGPoint
        let projectedDirection: CGVector
        let baseCopyCount: Int
        let pointsPerCopy: CGFloat
    }

    struct LinearDensityProjection: Sendable {
        let basePoint: CGPoint
        let extentPoint: CGPoint
        let anchorPoint: CGPoint
        let projectedDirection: CGVector
        let baseCopyCount: Int
        let pointsPerCopy: CGFloat
    }

    struct AngularCopyCountProjection: Sendable {
        let center: CGPoint
        let radialVector: CGVector
        let tangentVector: CGVector
        let baseCopyCount: Int
        let stepAngleRadians: Double
        let minimumAngleRadians: Double
    }

    struct AngularDensityProjection: Sendable {
        let anchorPoint: CGPoint
        let projectedDirection: CGVector
        let baseCopyCount: Int
        let pointsPerCopy: CGFloat
    }

    struct CurveCopyCountProjection: Sendable {
        let anchorPoint: CGPoint
        let projectedDirection: CGVector
        let baseCopyCount: Int
        let pointsPerCopy: CGFloat
    }

    struct CurveExtentProjection: Sendable {
        let projectedPathPoints: [CGPoint]
        let distanceSamplesMeters: [Double]
        let baseDistanceMeters: Double
        let totalLengthMeters: Double
        let minimumDistanceMeters: Double
    }

    struct OutputModeProjection: Sendable {
        let center: CGPoint
        let hitRect: CGRect
    }

    case projectionFree(ViewportSpatialPreparedInteractionTarget)
    case patternArrayRadialAngle(
        source: ViewportPatternAffordanceSource.RadialAngleHandle,
        projection: RadialProjection
    )
    case patternArrayCopyCountLinear(
        source: ViewportPatternAffordanceSource.CopyCountHandle,
        projection: LinearCopyCountProjection
    )
    case patternArrayCopyCountLinearDensity(
        source: ViewportPatternAffordanceSource.CopyCountHandle,
        projection: LinearDensityProjection
    )
    case patternArrayCopyCountAngular(
        source: ViewportPatternAffordanceSource.CopyCountHandle,
        projection: AngularCopyCountProjection
    )
    case patternArrayCopyCountAngularDensity(
        source: ViewportPatternAffordanceSource.CopyCountHandle,
        projection: AngularDensityProjection
    )
    case patternArrayCopyCountCurve(
        source: ViewportPatternAffordanceSource.CopyCountHandle,
        projection: CurveCopyCountProjection
    )
    case patternArrayCurveExtent(
        source: ViewportPatternAffordanceSource.CurveExtentHandle,
        projection: CurveExtentProjection
    )
    case patternArrayOutputMode(
        source: ViewportPatternAffordanceSource.OutputModeHandle,
        projection: OutputModeProjection
    )
}

extension ViewportSpatialInteractionRecord {
    /// Materializes one prepared record against the exact mounted native
    /// projection.  The closure is borrowed for this call and is never
    /// retained by the resulting value.
    @MainActor
    func materialize(
        using project: (Point3D) throws -> CGPoint
    ) throws -> ViewportSpatialMaterializedInteractionTarget {
        try target.materialize(using: project)
    }
}

extension ViewportSpatialPreparedInteractionTarget {
    /// Materializes a prepared semantic target without consulting legacy
    /// selectors, ViewportLayout, or mutable scene state.
    @MainActor
    func materialize(
        using project: (Point3D) throws -> CGPoint
    ) throws -> ViewportSpatialMaterializedInteractionTarget {
        switch self {
        // The axis owner claims these routes and re-queries the mounted camera on
        // each update, so this boundary must not answer for them.
        case .sketchCurveHandle, .sketchDimension, .sketchPointHandle,
             .splineControlPoint, .splineControlPointSlide,
             .polySplineSurfaceVertex, .polySplineSurfaceVertexSlide,
             .surfaceControlPoint, .surfaceControlPointSlide,
             .surfaceTrimEndpoint, .surfaceTrimControlPoint, .surfaceFrame,
             .regionOffset, .edgeOffset, .slotWidth, .sketchVertexOffset,
             .affordance, .objectTransform, .patternArrayLinearAxis,
             .independentCopyExtrudeDistance, .independentCopyBodyDimension,
             .bridgeCurveEndpoint, .constructionPlane, .patternArrayCurvePathPoint:
            return .projectionFree(self)

        case .patternArrayRadialAngle(let source):
            return .patternArrayRadialAngle(
                source: source,
                projection: try Self.radialProjection(
                    center: source.center,
                    axis: source.axis,
                    referencePoint: source.referencePoint,
                    angleRadians: source.angleRadians,
                    project: project
                )
            )

        case .patternArrayCopyCount(let source):
            switch source.guide {
            case .linear(let basePoint, let direction, let distanceMeters, let distanceMode):
                let projection = try Self.linearCopyCountProjection(
                    basePoint: basePoint,
                    direction: direction,
                    distanceMeters: distanceMeters,
                    copyCount: source.copyCount,
                    distanceMode: distanceMode,
                    project: project
                )
                switch distanceMode {
                case .spacing:
                    return .patternArrayCopyCountLinear(source: source, projection: projection.linear)
                case .extent:
                    return .patternArrayCopyCountLinearDensity(source: source, projection: projection.density)
                }

            case .radial(let center, let axis, let referencePoint, let angleRadians, let angleMode):
                switch angleMode {
                case .spacing:
                    return .patternArrayCopyCountAngular(
                        source: source,
                        projection: try Self.angularCopyCountProjection(
                            center: center,
                            axis: axis,
                            referencePoint: referencePoint,
                            angleRadians: angleRadians,
                            copyCount: source.copyCount,
                            project: project
                        )
                    )
                case .extent:
                    return .patternArrayCopyCountAngularDensity(
                        source: source,
                        projection: try Self.angularDensityProjection(
                            center: center,
                            axis: axis,
                            referencePoint: referencePoint,
                            angleRadians: angleRadians,
                            copyCount: source.copyCount,
                            project: project
                        )
                    )
                }

            case .curve(let pathPoints, let extentDistanceMeters):
                return .patternArrayCopyCountCurve(
                    source: source,
                    projection: try Self.curveCopyCountProjection(
                        pathPoints: pathPoints,
                        extentDistanceMeters: extentDistanceMeters,
                        copyCount: source.copyCount,
                        project: project
                    )
                )
            }

        case .patternArrayCurveExtent(let source):
            guard source.distanceMeters.isFinite, source.distanceMeters > 0.0 else {
                throw RealityViewportSpatialBatch.invalid("Pattern curve extent input is invalid.")
            }
            let path = try Self.projectedCurvePath(source.pathPoints, project: project)
            let minimumDistance = PatternArrayDistancePolicy.standard.minimumLinearDistanceMeters
            guard path.totalLengthMeters > minimumDistance else {
                throw RealityViewportSpatialBatch.invalid("Pattern curve path is too short for extent input.")
            }
            let baseDistance = min(max(source.distanceMeters, minimumDistance), path.totalLengthMeters)
            return .patternArrayCurveExtent(
                source: source,
                projection: .init(
                    projectedPathPoints: path.projectedPoints,
                    distanceSamplesMeters: path.distanceSamplesMeters,
                    baseDistanceMeters: baseDistance,
                    totalLengthMeters: path.totalLengthMeters,
                    minimumDistanceMeters: minimumDistance
                )
            )

        case .patternArrayOutputMode(let source):
            let anchor = try Self.finiteProjection(source.anchor, project: project)
            let center = CGPoint(x: anchor.x + 46.0, y: anchor.y - 34.0)
            let hitRect = CGRect(x: center.x - 78.0, y: center.y - 13.0, width: 156.0, height: 26.0)
            guard Self.finite(center), Self.finite(hitRect) else {
                throw RealityViewportSpatialBatch.invalid("Pattern output-mode projection is not finite.")
            }
            return .patternArrayOutputMode(
                source: source,
                projection: .init(center: center, hitRect: hitRect)
            )
        }
    }
}

private extension ViewportSpatialPreparedInteractionTarget {
    struct LinearCopyCountProjectionPair {
        let linear: ViewportSpatialMaterializedInteractionTarget.LinearCopyCountProjection
        let density: ViewportSpatialMaterializedInteractionTarget.LinearDensityProjection
    }

    static func linearCopyCountProjection(
        basePoint: Point3D,
        direction: Vector3D,
        distanceMeters: Double,
        copyCount: Int,
        distanceMode: PatternArrayDistanceMode,
        project: (Point3D) throws -> CGPoint
    ) throws -> LinearCopyCountProjectionPair {
        guard copyCount > 0 else {
            throw RealityViewportSpatialBatch.invalid("Pattern copy count is not positive.")
        }
        let unit = try unitVector(direction, message: "Linear copy-count direction is degenerate.")
        guard distanceMeters.isFinite, distanceMeters > 0.0 else {
            throw RealityViewportSpatialBatch.invalid("Linear copy-count distance is invalid.")
        }
        let base = try finiteProjection(basePoint, project: project)
        let tip = try finiteProjection(add(basePoint, unit), project: project)
        let projected = vector(from: base, to: tip)
        let projectedLength = vectorLength(projected)
        guard projectedLength.isFinite, projectedLength > 1.0e-9 else {
            throw RealityViewportSpatialBatch.invalid("Linear copy-count projection is degenerate.")
        }
        let projectedDirection = normalized(projected)
        let spacing = max(CGFloat(distanceMeters) * projectedLength, 28.0)
        let extent = CGPoint(
            x: base.x + projectedDirection.dx * CGFloat(distanceMeters) * projectedLength,
            y: base.y + projectedDirection.dy * CGFloat(distanceMeters) * projectedLength
        )
        let normal = CGVector(dx: -projectedDirection.dy, dy: projectedDirection.dx)
        let anchor = CGPoint(
            x: extent.x + normal.dx * 24.0,
            y: extent.y + normal.dy * 24.0
        )
        guard finite(extent), finite(anchor), spacing.isFinite else {
            throw RealityViewportSpatialBatch.invalid("Linear copy-count projection is not finite.")
        }
        switch distanceMode {
        case .spacing:
            return .init(
                linear: .init(
                    basePoint: base,
                    projectedDirection: projectedDirection,
                    baseCopyCount: copyCount,
                    pointsPerCopy: spacing
                ),
                density: .init(
                    basePoint: base,
                    extentPoint: extent,
                    anchorPoint: anchor,
                    projectedDirection: projectedDirection,
                    baseCopyCount: copyCount,
                    pointsPerCopy: 28.0
                )
            )
        case .extent:
            return .init(
                linear: .init(
                    basePoint: base,
                    projectedDirection: projectedDirection,
                    baseCopyCount: copyCount,
                    pointsPerCopy: spacing
                ),
                density: .init(
                    basePoint: base,
                    extentPoint: extent,
                    anchorPoint: anchor,
                    projectedDirection: projectedDirection,
                    baseCopyCount: copyCount,
                    pointsPerCopy: 28.0
                )
            )
        }
    }

    static func radialProjection(
        center: Point3D,
        axis: Vector3D,
        referencePoint: Point3D,
        angleRadians: Double,
        project: (Point3D) throws -> CGPoint
    ) throws -> ViewportSpatialMaterializedInteractionTarget.RadialProjection {
        let frame = try radialFrame(center: center, axis: axis, referencePoint: referencePoint)
        let minimumAngle = PatternArrayAnglePolicy.standard.minimumAngleRadians
        let baseAngle = try normalizedAngle(angleRadians, minimum: minimumAngle)
        let centerPoint = try finiteProjection(center, project: project)
        let radialPoint = try finiteProjection(add(center, frame.radial), project: project)
        let tangentPoint = try finiteProjection(add(center, frame.tangent), project: project)
        let radial = vector(from: centerPoint, to: radialPoint)
        let tangent = vector(from: centerPoint, to: tangentPoint)
        let radialLength = vectorLength(radial)
        let tangentLength = vectorLength(tangent)
        guard radialLength > 1.0e-9, tangentLength > 1.0e-9 else {
            throw RealityViewportSpatialBatch.invalid("Radial pattern projection is degenerate.")
        }
        // A basis this camera collapses onto one screen line cannot recover a
        // rotation about the CAD axis, so the press is refused here rather than
        // answered with a screen-polar angle once the drag has started.
        let determinant = radial.dx * tangent.dy - radial.dy * tangent.dx
        let determinantScale = max(radialLength * tangentLength, 1.0)
        guard determinant.isFinite, determinantScale.isFinite,
              abs(determinant) > determinantScale * 1.0e-9 else {
            throw RealityViewportSpatialBatch.invalid(
                "Radial pattern projection cannot recover an angle from collinear samples."
            )
        }
        return .init(
            center: centerPoint,
            radialVector: radial,
            tangentVector: tangent,
            baseAngleRadians: baseAngle,
            minimumAngleRadians: minimumAngle
        )
    }

    static func angularCopyCountProjection(
        center: Point3D,
        axis: Vector3D,
        referencePoint: Point3D,
        angleRadians: Double,
        copyCount: Int,
        project: (Point3D) throws -> CGPoint
    ) throws -> ViewportSpatialMaterializedInteractionTarget.AngularCopyCountProjection {
        guard copyCount > 0 else {
            throw RealityViewportSpatialBatch.invalid("Angular copy count is not positive.")
        }
        // `radialProjection` already refuses a collinear projected basis, which
        // is the same condition this step needs to step an angle.
        let radial = try radialProjection(
            center: center, axis: axis, referencePoint: referencePoint,
            angleRadians: angleRadians, project: project
        )
        return .init(
            center: radial.center,
            radialVector: radial.radialVector,
            tangentVector: radial.tangentVector,
            baseCopyCount: copyCount,
            stepAngleRadians: radial.baseAngleRadians,
            minimumAngleRadians: radial.minimumAngleRadians
        )
    }

    static func angularDensityProjection(
        center: Point3D,
        axis: Vector3D,
        referencePoint: Point3D,
        angleRadians: Double,
        copyCount: Int,
        project: (Point3D) throws -> CGPoint
    ) throws -> ViewportSpatialMaterializedInteractionTarget.AngularDensityProjection {
        guard copyCount > 0, angleRadians.isFinite,
              abs(angleRadians) > PatternArrayAnglePolicy.standard.minimumAngleRadians else {
            throw RealityViewportSpatialBatch.invalid("Angular density input is invalid.")
        }
        let frame = try radialFrame(center: center, axis: axis, referencePoint: referencePoint)
        let endRadial = rotate(frame.radial, around: frame.axis, angle: angleRadians)
        let endpoint = add(center, endRadial)
        let centerPoint = try finiteProjection(center, project: project)
        let endpointPoint = try finiteProjection(endpoint, project: project)
        let outward = vector(from: centerPoint, to: endpointPoint)
        let outwardLength = vectorLength(outward)
        guard outwardLength.isFinite, outwardLength > 1.0e-9 else {
            throw RealityViewportSpatialBatch.invalid("Angular density projection is degenerate.")
        }
        let tangentWorld = scale(
            cross(frame.axis, endRadial),
            by: angleRadians < 0.0 ? -1.0 : 1.0
        )
        let projectedTangent = vector(
            from: endpointPoint,
            to: try finiteProjection(add(endpoint, tangentWorld), project: project)
        )
        let tangentLength = vectorLength(projectedTangent)
        guard tangentLength.isFinite, tangentLength > 1.0e-9 else {
            throw RealityViewportSpatialBatch.invalid("Angular density tangent projection is degenerate.")
        }
        let outwardUnit = normalized(outward)
        let anchor = CGPoint(
            x: endpointPoint.x + outwardUnit.dx * 24.0,
            y: endpointPoint.y + outwardUnit.dy * 24.0
        )
        guard finite(anchor) else {
            throw RealityViewportSpatialBatch.invalid("Angular density anchor is not finite.")
        }
        return .init(
            anchorPoint: anchor,
            projectedDirection: normalized(projectedTangent),
            baseCopyCount: copyCount,
            pointsPerCopy: 28.0
        )
    }

    static func curveCopyCountProjection(
        pathPoints: [Point3D],
        extentDistanceMeters: Double,
        copyCount: Int,
        project: (Point3D) throws -> CGPoint
    ) throws -> ViewportSpatialMaterializedInteractionTarget.CurveCopyCountProjection {
        guard pathPoints.count >= 2, extentDistanceMeters.isFinite, extentDistanceMeters > 0.0,
              copyCount > 0 else {
            throw RealityViewportSpatialBatch.invalid("Curve copy-count input is invalid.")
        }
        let path = try projectedCurvePath(pathPoints, project: project)
        let minimumDistance = PatternArrayDistancePolicy.standard.minimumLinearDistanceMeters
        guard path.totalLengthMeters > minimumDistance else {
            throw RealityViewportSpatialBatch.invalid("Curve copy-count path is too short.")
        }
        let baseDistance = min(max(extentDistanceMeters, minimumDistance), path.totalLengthMeters)
        let sample = try curveProjectionSample(at: baseDistance, path: path, points: pathPoints, project: project)
        let tip = sample.projectedPoint
        let direction = sample.projectedTangentDirection
        let normal = CGVector(dx: -direction.dy, dy: direction.dx)
        let anchor = CGPoint(x: tip.x + normal.dx * 24.0, y: tip.y + normal.dy * 24.0)
        guard finite(anchor) else {
            throw RealityViewportSpatialBatch.invalid("Curve copy-count anchor is not finite.")
        }
        return .init(
            anchorPoint: anchor,
            projectedDirection: direction,
            baseCopyCount: copyCount,
            pointsPerCopy: 28.0
        )
    }

    struct RadialFrame {
        let axis: Vector3D
        let radial: Vector3D
        let tangent: Vector3D
    }

    static func radialFrame(
        center: Point3D,
        axis: Vector3D,
        referencePoint: Point3D
    ) throws -> RadialFrame {
        guard finite(center), finite(axis), finite(referencePoint) else {
            throw RealityViewportSpatialBatch.invalid("Radial pattern source is not finite.")
        }
        let normalizedAxis = try unitVector(axis, message: "Radial pattern axis is degenerate.")
        var radial = subtract(vector(from: center, to: referencePoint),
                              scale(normalizedAxis, by: dot(vector(from: center, to: referencePoint), normalizedAxis)))
        if vectorLength(radial) <= PatternArrayDistancePolicy.standard.minimumLinearDistanceMeters {
            let helper = abs(normalizedAxis.z) < 0.9 ? Vector3D.unitZ : Vector3D.unitY
            radial = subtract(helper, scale(normalizedAxis, by: dot(helper, normalizedAxis)))
            let fallbackLength = vectorLength(radial)
            guard fallbackLength.isFinite, fallbackLength > 1.0e-12 else {
                throw RealityViewportSpatialBatch.invalid("Radial pattern fallback is degenerate.")
            }
            radial = scale(scale(radial, by: 1.0 / fallbackLength), by: 0.05)
        }
        guard vectorLength(radial) > PatternArrayDistancePolicy.standard.minimumLinearDistanceMeters else {
            throw RealityViewportSpatialBatch.invalid("Radial pattern reference is degenerate.")
        }
        let tangent = cross(normalizedAxis, radial)
        guard vectorLength(tangent) > PatternArrayDistancePolicy.standard.minimumLinearDistanceMeters else {
            throw RealityViewportSpatialBatch.invalid("Radial pattern tangent is degenerate.")
        }
        return .init(axis: normalizedAxis, radial: radial, tangent: tangent)
    }

    static func projectedPath(
        _ points: [Point3D],
        project: (Point3D) throws -> CGPoint
    ) throws -> [CGPoint] {
        guard !points.isEmpty else {
            throw RealityViewportSpatialBatch.invalid("Projected path has no points.")
        }
        var result: [CGPoint] = []
        result.reserveCapacity(points.count)
        for point in points {
            result.append(try finiteProjection(point, project: project))
        }
        return result
    }

    struct ProjectedCurvePath {
        let projectedPoints: [CGPoint]
        let distanceSamplesMeters: [Double]
        let totalLengthMeters: Double
    }

    struct CurveProjectionSample {
        let projectedPoint: CGPoint
        let projectedTangentDirection: CGVector
    }

    static func projectedCurvePath(
        _ points: [Point3D],
        project: (Point3D) throws -> CGPoint
    ) throws -> ProjectedCurvePath {
        guard points.count >= 2 else {
            throw RealityViewportSpatialBatch.invalid("Projected curve has fewer than two points.")
        }
        let projectedPoints = try projectedPath(points, project: project)
        var distances: [Double] = [0.0]
        distances.reserveCapacity(points.count)
        var totalLength = 0.0
        for index in 1 ..< points.count {
            let span = vectorLength(vector(from: points[index - 1], to: points[index]))
            guard span.isFinite, span > 1.0e-12 else {
                throw RealityViewportSpatialBatch.invalid("Projected curve contains a degenerate span.")
            }
            totalLength += span
            guard totalLength.isFinite else {
                throw RealityViewportSpatialBatch.invalid("Projected curve length is not finite.")
            }
            distances.append(totalLength)
        }
        guard totalLength > 1.0e-12 else {
            throw RealityViewportSpatialBatch.invalid("Projected curve has no length.")
        }
        return .init(
            projectedPoints: projectedPoints,
            distanceSamplesMeters: distances,
            totalLengthMeters: totalLength
        )
    }

    static func curveProjectionSample(
        at distanceMeters: Double,
        path: ProjectedCurvePath,
        points: [Point3D],
        project: (Point3D) throws -> CGPoint
    ) throws -> CurveProjectionSample {
        guard distanceMeters.isFinite else {
            throw RealityViewportSpatialBatch.invalid("Projected curve distance is not finite.")
        }
        let distance = min(max(distanceMeters, 0.0), path.totalLengthMeters)
        for index in 1 ..< path.projectedPoints.count {
            let previousDistance = path.distanceSamplesMeters[index - 1]
            let nextDistance = path.distanceSamplesMeters[index]
            let span = nextDistance - previousDistance
            guard span > 1.0e-12 else {
                continue
            }
            guard distance <= nextDistance || index == path.projectedPoints.count - 1 else {
                continue
            }
            let ratio = min(max((distance - previousDistance) / span, 0.0), 1.0)
            let worldSegment = vector(from: points[index - 1], to: points[index])
            let worldPoint = add(points[index - 1], scale(worldSegment, by: ratio))
            let projectedPoint = try finiteProjection(worldPoint, project: project)
            let tangentTip = try finiteProjection(add(worldPoint, scale(worldSegment, by: 1.0 / span)), project: project)
            let segment = vector(from: projectedPoint, to: tangentTip)
            let segmentLength = vectorLength(segment)
            guard segmentLength.isFinite, segmentLength > 1.0e-9 else {
                throw RealityViewportSpatialBatch.invalid("Projected curve tangent is degenerate.")
            }
            return .init(
                projectedPoint: projectedPoint,
                projectedTangentDirection: normalized(segment)
            )
        }
        throw RealityViewportSpatialBatch.invalid("Projected curve tangent is unavailable.")
    }

    static func finiteProjection(
        _ point: Point3D,
        project: (Point3D) throws -> CGPoint
    ) throws -> CGPoint {
        guard finite(point) else {
            throw RealityViewportSpatialBatch.invalid("Materialized world point is not finite.")
        }
        let result = try project(point)
        guard finite(result) else {
            throw RealityViewportSpatialBatch.invalid("Native projection is not finite.")
        }
        return result
    }

    static func normalizedAngle(_ value: Double, minimum: Double) throws -> Double {
        guard value.isFinite, minimum.isFinite, minimum > 0.0 else {
            throw RealityViewportSpatialBatch.invalid("Pattern angle is invalid.")
        }
        guard abs(value) < minimum else { return value }
        return value < 0.0 ? -minimum : minimum
    }

    static func unitVector(_ vector: Vector3D, message: String) throws -> Vector3D {
        let length = vectorLength(vector)
        guard length.isFinite, length > 1.0e-12 else {
            throw RealityViewportSpatialBatch.invalid(message)
        }
        return scale(vector, by: 1.0 / length)
    }

    static func rotate(_ vector: Vector3D, around axis: Vector3D, angle: Double) -> Vector3D {
        let cosine = cos(angle)
        let sine = sin(angle)
        return add(
            add(scale(vector, by: cosine), scale(cross(axis, vector), by: sine)),
            scale(axis, by: dot(axis, vector) * (1.0 - cosine))
        )
    }

    static func vector(from start: Point3D, to end: Point3D) -> Vector3D {
        Vector3D(x: end.x - start.x, y: end.y - start.y, z: end.z - start.z)
    }

    static func vector(from start: CGPoint, to end: CGPoint) -> CGVector {
        CGVector(dx: end.x - start.x, dy: end.y - start.y)
    }

    static func add(_ point: Point3D, _ vector: Vector3D) -> Point3D {
        Point3D(x: point.x + vector.x, y: point.y + vector.y, z: point.z + vector.z)
    }

    static func add(_ lhs: Vector3D, _ rhs: Vector3D) -> Vector3D {
        Vector3D(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    static func subtract(_ lhs: Vector3D, _ rhs: Vector3D) -> Vector3D {
        Vector3D(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    static func scale(_ vector: Vector3D, by scalar: Double) -> Vector3D {
        Vector3D(x: vector.x * scalar, y: vector.y * scalar, z: vector.z * scalar)
    }

    static func dot(_ lhs: Vector3D, _ rhs: Vector3D) -> Double {
        lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
    }

    static func cross(_ lhs: Vector3D, _ rhs: Vector3D) -> Vector3D {
        Vector3D(
            x: lhs.y * rhs.z - lhs.z * rhs.y,
            y: lhs.z * rhs.x - lhs.x * rhs.z,
            z: lhs.x * rhs.y - lhs.y * rhs.x
        )
    }

    static func vectorLength(_ vector: Vector3D) -> Double {
        (vector.x * vector.x + vector.y * vector.y + vector.z * vector.z).squareRoot()
    }

    static func vectorLength(_ vector: CGVector) -> CGFloat {
        hypot(vector.dx, vector.dy)
    }

    static func normalized(_ vector: CGVector) -> CGVector {
        let length = vectorLength(vector)
        return CGVector(dx: vector.dx / length, dy: vector.dy / length)
    }

    static func finite(_ point: Point3D) -> Bool {
        point.x.isFinite && point.y.isFinite && point.z.isFinite
    }

    static func finite(_ vector: Vector3D) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    }

    static func finite(_ point: CGPoint) -> Bool {
        point.x.isFinite && point.y.isFinite
    }

    static func finite(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.size.width.isFinite && rect.size.height.isFinite
            && rect.width >= 0.0 && rect.height >= 0.0
            && rect.maxX.isFinite && rect.maxY.isFinite
    }
}
