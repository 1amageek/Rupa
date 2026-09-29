import SwiftCAD
import RupaCoreTypes

struct BSplineSurfaceControlPointEditingService: Sendable {
    let tolerance: ModelingTolerance

    init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

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
        try updatedFeature.validate(tolerance: tolerance)
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
        try updatedFeature.validate(tolerance: tolerance)
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
        try SurfaceControlHullSlideFrame(
            controlPoints: feature.surface.controlPoints, uIndex: target.uIndex, vIndex: target.vIndex, owner: "B-spline surface control point slide"
        ).vector(for: direction)
    }
}
