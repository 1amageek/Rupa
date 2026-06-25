import SwiftCAD

struct PolySplineSurfaceControlPointEditingService: Sendable {
    func updatedPolySpline(
        moving target: PolySplineSurfaceControlPointEditTarget,
        by delta: Vector3D,
        in polySpline: PolySplineFeature,
        owner: String
    ) throws -> PolySplineFeature {
        let currentPoint = try controlPoint(for: target, in: polySpline, owner: owner)
        let updatedPoint = currentPoint + delta
        var updatedPolySpline = polySpline
        let override = PolySplineSurfaceControlPointOverride(
            patchID: target.patchID,
            uIndex: target.uIndex,
            vIndex: target.vIndex,
            point: updatedPoint
        )
        if let existingIndex = updatedPolySpline.controlPointOverrides.firstIndex(where: { $0.address == target.address }) {
            updatedPolySpline.controlPointOverrides[existingIndex] = override
        } else {
            updatedPolySpline.controlPointOverrides.append(override)
        }
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

    func slideUnitVector(
        for target: PolySplineSurfaceControlPointEditTarget,
        in polySpline: PolySplineFeature,
        direction: PolySplineSurfaceVertexSlideDirection
    ) throws -> Vector3D {
        let patch = try supportedPatch(
            for: target,
            in: polySpline,
            owner: "PolySpline surface control point slide"
        )
        let bottomU = patch.boundaryPoints[1] - patch.boundaryPoints[0]
        let topU = patch.boundaryPoints[2] - patch.boundaryPoints[3]
        let leftV = patch.boundaryPoints[3] - patch.boundaryPoints[0]
        let rightV = patch.boundaryPoints[2] - patch.boundaryPoints[1]
        let positiveU = try normalizedSlideVector(
            (bottomU + topU) / 2.0,
            owner: "Positive U"
        )
        let positiveV = try normalizedSlideVector(
            (leftV + rightV) / 2.0,
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

    private func controlPoints(
        for target: PolySplineSurfaceControlPointEditTarget,
        in polySpline: PolySplineFeature,
        owner: String
    ) throws -> [[Point3D]] {
        try target.address.validate()
        let patch = try supportedPatch(for: target, in: polySpline, owner: owner)
        let surface = BSplineSurface3D.cubicBezierPatch(
            bottomLeft: patch.boundaryPoints[0],
            bottomRight: patch.boundaryPoints[1],
            topRight: patch.boundaryPoints[2],
            topLeft: patch.boundaryPoints[3]
        )
        var controlPoints = surface.controlPoints
        for override in polySpline.controlPointOverrides where override.patchID == target.patchID {
            do {
                try override.validate()
            } catch {
                throw EditorError(
                    code: .commandInvalid,
                    message: "\(owner) contains an invalid PolySpline surface control point override: \(String(describing: error))."
                )
            }
            guard controlPoints.indices.contains(override.vIndex),
                  controlPoints[override.vIndex].indices.contains(override.uIndex) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(owner) references a missing PolySpline surface control point override target."
                )
            }
            controlPoints[override.vIndex][override.uIndex] = override.point
        }
        return controlPoints
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
