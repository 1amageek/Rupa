import SwiftCAD
import RupaCoreTypes

struct BSplineSurfaceControlPointEditingService: Sendable {
    func updatedFeature(
        moving target: BSplineSurfaceControlPointEditTarget,
        by delta: Vector3D,
        in feature: BSplineSurfaceFeature,
        owner: String
    ) throws -> BSplineSurfaceFeature {
        try delta.validate()
        let currentPoint = try controlPoint(for: target, in: feature, owner: owner)
        var updatedFeature = feature
        updatedFeature.surface.controlPoints[target.vIndex][target.uIndex] = currentPoint + delta
        try updatedFeature.validate()
        return updatedFeature
    }

    func updatedFeature(
        settingWeight weight: Double,
        for target: BSplineSurfaceControlPointEditTarget,
        in feature: BSplineSurfaceFeature,
        owner: String
    ) throws -> BSplineSurfaceFeature {
        guard weight.isFinite else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a finite control point weight."
            )
        }
        guard weight > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a positive control point weight."
            )
        }
        _ = try controlPoint(for: target, in: feature, owner: owner)
        var updatedFeature = feature
        updatedFeature.surface.weights[target.vIndex][target.uIndex] = weight
        try updatedFeature.validate()
        return updatedFeature
    }

    func controlPoint(
        for target: BSplineSurfaceControlPointEditTarget,
        in feature: BSplineSurfaceFeature,
        owner: String
    ) throws -> Point3D {
        guard feature.surface.controlPoints.indices.contains(target.vIndex),
              feature.surface.controlPoints[target.vIndex].indices.contains(target.uIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) references a missing B-spline surface control point."
            )
        }
        let point = feature.surface.controlPoints[target.vIndex][target.uIndex]
        try point.validate()
        return point
    }

    func controlPointWeight(
        for target: BSplineSurfaceControlPointEditTarget,
        in feature: BSplineSurfaceFeature,
        owner: String
    ) throws -> Double {
        guard feature.surface.weights.indices.contains(target.vIndex),
              feature.surface.weights[target.vIndex].indices.contains(target.uIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) references a missing B-spline surface control point weight."
            )
        }
        let weight = feature.surface.weights[target.vIndex][target.uIndex]
        guard weight.isFinite, weight > 0.0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) references an invalid B-spline surface control point weight."
            )
        }
        return weight
    }

    func slideUnitVector(
        for target: BSplineSurfaceControlPointEditTarget,
        in feature: BSplineSurfaceFeature,
        direction: PolySplineSurfaceVertexSlideDirection
    ) throws -> Vector3D {
        let positiveU = try normalizedSlideVector(
            hullDirection(
                at: target,
                in: feature.surface.controlPoints,
                axis: .u,
                owner: "Positive U"
            ),
            owner: "Positive U"
        )
        let positiveV = try normalizedSlideVector(
            hullDirection(
                at: target,
                in: feature.surface.controlPoints,
                axis: .v,
                owner: "Positive V"
            ),
            owner: "Positive V"
        )
        let normal = try normalizedSlideVector(
            positiveU.cross(positiveV),
            owner: "Normal"
        )

        switch direction {
        case .positiveU:
            return positiveU
        case .negativeU:
            return -positiveU
        case .normal:
            return normal
        case .positiveV:
            return positiveV
        case .negativeV:
            return -positiveV
        }
    }

    private enum ControlPointDirectionAxis {
        case u
        case v
    }

    private func hullDirection(
        at target: BSplineSurfaceControlPointEditTarget,
        in controlPoints: [[Point3D]],
        axis: ControlPointDirectionAxis,
        owner: String
    ) throws -> Vector3D {
        guard controlPoints.indices.contains(target.vIndex),
              controlPoints[target.vIndex].indices.contains(target.uIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) references a missing B-spline surface control point."
            )
        }

        let count = axis == .u ? controlPoints[target.vIndex].count : controlPoints.count
        let index = axis == .u ? target.uIndex : target.vIndex
        guard count >= 2, (0 ..< count).contains(index) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) cannot resolve a B-spline surface control hull direction."
            )
        }

        let lowerIndex = max(index - 1, 0)
        let upperIndex = min(index + 1, count - 1)
        guard lowerIndex != upperIndex else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) control hull direction is collapsed for B-spline surface control point slide."
            )
        }

        switch axis {
        case .u:
            return controlPoints[target.vIndex][upperIndex] - controlPoints[target.vIndex][lowerIndex]
        case .v:
            return controlPoints[upperIndex][target.uIndex] - controlPoints[lowerIndex][target.uIndex]
        }
    }

    private func normalizedSlideVector(
        _ vector: Vector3D,
        owner: String
    ) throws -> Vector3D {
        do {
            return try vector.normalized(tolerance: ModelingTolerance.standard.distance)
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) direction is collapsed for B-spline surface control point slide."
            )
        }
    }
}
