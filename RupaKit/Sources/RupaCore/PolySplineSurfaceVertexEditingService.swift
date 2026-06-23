import SwiftCAD

struct PolySplineSurfaceVertexEditingService: Sendable {
    func sourceVertexIndex(
        for target: PolySplineSurfaceVertexTarget,
        in polySpline: PolySplineFeature,
        owner: String
    ) throws -> Int {
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
        let boundaryIndex = target.boundaryRole.boundaryIndex
        guard patch.boundaryVertexIndices.indices.contains(boundaryIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) requires an existing patch boundary vertex."
            )
        }
        return patch.boundaryVertexIndices[boundaryIndex]
    }

    func validateTargetStillStable(
        _ target: PolySplineSurfaceVertexTarget,
        sourceVertexIndex: Int,
        in polySpline: PolySplineFeature,
        owner: String
    ) throws {
        let analysis = PolySplineMeshAnalyzer().analyze(
            mesh: polySpline.sourceMesh,
            options: polySpline.options
        )
        guard analysis.result.isSupported else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) would leave the source mesh unsupported: \(analysis.result.failureMessage ?? "No supported patch candidate.")"
            )
        }
        guard let patch = analysis.supportedPatches.first(where: { $0.candidateID == target.patchID }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) would remove the selected patch from the reconstruction."
            )
        }
        let boundaryIndex = target.boundaryRole.boundaryIndex
        guard patch.boundaryVertexIndices.indices.contains(boundaryIndex),
              patch.boundaryVertexIndices[boundaryIndex] == sourceVertexIndex else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) would change the selected patch boundary role."
            )
        }
    }

    func slideUnitVector(
        for target: PolySplineSurfaceVertexTarget,
        in polySpline: PolySplineFeature,
        direction: PolySplineSurfaceVertexSlideDirection
    ) throws -> Vector3D {
        let analysis = PolySplineMeshAnalyzer().analyze(
            mesh: polySpline.sourceMesh,
            options: polySpline.options
        )
        guard analysis.result.isSupported else {
            throw EditorError(
                code: .commandInvalid,
                message: "PolySpline surface vertex slide requires a supported PolySpline source mesh."
            )
        }
        guard let patch = analysis.supportedPatches.first(where: { $0.candidateID == target.patchID }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "PolySpline surface vertex slide requires an existing patch target."
            )
        }

        func boundaryPoint(_ role: PolySplineSurfaceVertexTarget.BoundaryRole) throws -> Point3D {
            let boundaryIndex = role.boundaryIndex
            guard patch.boundaryVertexIndices.indices.contains(boundaryIndex) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "PolySpline surface vertex slide requires an existing patch boundary vertex."
                )
            }
            let sourceVertexIndex = patch.boundaryVertexIndices[boundaryIndex]
            guard polySpline.sourceMesh.positions.indices.contains(sourceVertexIndex) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "PolySpline surface vertex slide references a missing source mesh vertex."
                )
            }
            return polySpline.sourceMesh.positions[sourceVertexIndex]
        }

        let positiveURaw: Vector3D
        switch target.boundaryRole {
        case .uMinVMin, .uMaxVMin:
            positiveURaw = try boundaryPoint(.uMaxVMin) - boundaryPoint(.uMinVMin)
        case .uMaxVMax, .uMinVMax:
            positiveURaw = try boundaryPoint(.uMaxVMax) - boundaryPoint(.uMinVMax)
        }

        let positiveVRaw: Vector3D
        switch target.boundaryRole {
        case .uMinVMin, .uMinVMax:
            positiveVRaw = try boundaryPoint(.uMinVMax) - boundaryPoint(.uMinVMin)
        case .uMaxVMin, .uMaxVMax:
            positiveVRaw = try boundaryPoint(.uMaxVMax) - boundaryPoint(.uMaxVMin)
        }

        let positiveU = try normalizedSlideVector(
            positiveURaw,
            owner: "Positive U"
        )
        let positiveV = try normalizedSlideVector(
            positiveVRaw,
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
            return negatedSlideVector(positiveU)
        case .normal:
            return normal
        case .positiveV:
            return positiveV
        case .negativeV:
            return negatedSlideVector(positiveV)
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
                message: "\(owner) direction is collapsed for PolySpline surface vertex slide."
            )
        }
    }

    private func negatedSlideVector(_ vector: Vector3D) -> Vector3D {
        Vector3D(x: -vector.x, y: -vector.y, z: -vector.z)
    }
}
