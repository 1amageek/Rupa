import SwiftCAD
import RupaCoreTypes

struct PolySplineSurfaceControlPointEditingService: Sendable {
    func updatedPolySpline(
        moving target: PolySplineSurfaceControlPointEditTarget,
        by delta: Vector3D,
        in polySpline: PolySplineFeature,
        owner: String
    ) throws -> PolySplineFeature {
        let currentPoint = try controlPoint(for: target, in: polySpline, owner: owner)
        let updatedPoint = currentPoint + delta
        let currentWeight = try controlPointWeight(for: target, in: polySpline, owner: owner)
        var updatedPolySpline = polySpline
        let override = PolySplineSurfaceControlPointOverride(
            patchID: target.patchID,
            uIndex: target.uIndex,
            vIndex: target.vIndex,
            point: updatedPoint,
            weight: currentWeight
        )
        upsert(override, in: &updatedPolySpline)
        try updatedPolySpline.validate()
        return updatedPolySpline
    }

    func updatedPolySpline(
        settingWeight weight: Double,
        for target: PolySplineSurfaceControlPointEditTarget,
        in polySpline: PolySplineFeature,
        owner: String
    ) throws -> PolySplineFeature {
        let currentPoint = try controlPoint(for: target, in: polySpline, owner: owner)
        var updatedPolySpline = polySpline
        let override = PolySplineSurfaceControlPointOverride(
            patchID: target.patchID,
            uIndex: target.uIndex,
            vIndex: target.vIndex,
            point: currentPoint,
            weight: weight
        )
        upsert(override, in: &updatedPolySpline)
        try updatedPolySpline.validate()
        return updatedPolySpline
    }

    func controlPoint(
        for target: PolySplineSurfaceControlPointEditTarget,
        in polySpline: PolySplineFeature,
        owner: String
    ) throws -> Point3D {
        let controlPoints = try controlPoints(for: target, in: polySpline, owner: owner)
        guard controlPoints.indices.contains(target.vIndex),
              controlPoints[target.vIndex].indices.contains(target.uIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) references a missing surface control point."
            )
        }
        return controlPoints[target.vIndex][target.uIndex]
    }

    func controlPointWeight(
        for target: PolySplineSurfaceControlPointEditTarget,
        in polySpline: PolySplineFeature,
        owner: String
    ) throws -> Double {
        let surface = try surface(for: target, in: polySpline, owner: owner)
        guard surface.weights.indices.contains(target.vIndex),
              surface.weights[target.vIndex].indices.contains(target.uIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) references a missing surface control point weight."
            )
        }
        return surface.weights[target.vIndex][target.uIndex]
    }

    func slideUnitVector(
        for target: PolySplineSurfaceControlPointEditTarget,
        in polySpline: PolySplineFeature,
        direction: PolySplineSurfaceVertexSlideDirection
    ) throws -> Vector3D {
        let controlPoints = try controlPoints(
            for: target,
            in: polySpline,
            owner: "PolySpline surface control point slide"
        )
        let positiveU = try normalizedSlideVector(
            hullDirection(
                at: target,
                in: controlPoints,
                axis: .u,
                owner: "Positive U"
            ),
            owner: "Positive U"
        )
        let positiveV = try normalizedSlideVector(
            hullDirection(
                at: target,
                in: controlPoints,
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
        at target: PolySplineSurfaceControlPointEditTarget,
        in controlPoints: [[Point3D]],
        axis: ControlPointDirectionAxis,
        owner: String
    ) throws -> Vector3D {
        guard controlPoints.indices.contains(target.vIndex),
              controlPoints[target.vIndex].indices.contains(target.uIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) references a missing surface control point."
            )
        }

        let count = axis == .u ? controlPoints[target.vIndex].count : controlPoints.count
        let index = axis == .u ? target.uIndex : target.vIndex
        guard count >= 2, (0 ..< count).contains(index) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) cannot resolve a surface control hull direction."
            )
        }

        let lowerIndex = max(index - 1, 0)
        let upperIndex = min(index + 1, count - 1)
        guard lowerIndex != upperIndex else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) control hull direction is collapsed for PolySpline surface control point slide."
            )
        }

        switch axis {
        case .u:
            return controlPoints[target.vIndex][upperIndex] - controlPoints[target.vIndex][lowerIndex]
        case .v:
            return controlPoints[upperIndex][target.uIndex] - controlPoints[lowerIndex][target.uIndex]
        }
    }

    private func surface(
        for target: PolySplineSurfaceControlPointEditTarget,
        in polySpline: PolySplineFeature,
        owner: String
    ) throws -> BSplineSurface3D {
        let patch = try supportedPatch(
            for: target,
            in: polySpline,
            owner: owner
        )
        var surface = BSplineSurface3D.cubicBezierPatch(
            bottomLeft: patch.boundaryPoints[0],
            bottomRight: patch.boundaryPoints[1],
            topRight: patch.boundaryPoints[2],
            topLeft: patch.boundaryPoints[3]
        )
        for override in polySpline.controlPointOverrides where override.patchID == target.patchID {
            do {
                try override.validate()
            } catch {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) contains an invalid PolySpline surface control point override: \(String(describing: error))."
                )
            }
            guard surface.controlPoints.indices.contains(override.vIndex),
                  surface.controlPoints[override.vIndex].indices.contains(override.uIndex),
                  surface.weights.indices.contains(override.vIndex),
                  surface.weights[override.vIndex].indices.contains(override.uIndex) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(owner) references a missing PolySpline surface control point override target."
                )
            }
            surface.controlPoints[override.vIndex][override.uIndex] = override.point
            surface.weights[override.vIndex][override.uIndex] = override.weight
        }
        return surface
    }

    private func upsert(
        _ override: PolySplineSurfaceControlPointOverride,
        in polySpline: inout PolySplineFeature
    ) {
        if let existingIndex = polySpline.controlPointOverrides.firstIndex(where: { $0.address == override.address }) {
            polySpline.controlPointOverrides[existingIndex] = override
        } else {
            polySpline.controlPointOverrides.append(override)
        }
    }

    private func controlPoints(
        for target: PolySplineSurfaceControlPointEditTarget,
        in polySpline: PolySplineFeature,
        owner: String
    ) throws -> [[Point3D]] {
        try surface(for: target, in: polySpline, owner: owner).controlPoints
    }

    private func supportedPatch(
        for target: PolySplineSurfaceControlPointEditTarget,
        in polySpline: PolySplineFeature,
        owner: String
    ) throws -> PolySplineMeshAnalyzer.Analysis.SupportedPatch {
        try target.address.validate()
        let analysis = PolySplineMeshAnalyzer().analyze(
            mesh: polySpline.sourceMesh,
            options: polySpline.options
        )
        guard analysis.result.isSupported else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a supported PolySpline source mesh."
            )
        }
        guard let patch = analysis.supportedPatches.first(where: { $0.candidateID == target.patchID }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) requires an existing patch target."
            )
        }
        return patch
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
                message: "\(owner) direction is collapsed for PolySpline surface control point slide."
            )
        }
    }
}
