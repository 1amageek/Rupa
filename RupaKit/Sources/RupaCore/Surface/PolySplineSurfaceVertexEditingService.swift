import SwiftCAD
import RupaCoreTypes

struct PolySplineSurfaceVertexEditingService: Sendable {
    let tolerance: ModelingTolerance

    init(tolerance: ModelingTolerance) {
        self.tolerance = tolerance
    }

    func sourceVertexIndex(
        for target: PolySplineSurfaceVertexTarget,
        in polySpline: PolySplineFeature,
        owner: String
    ) throws -> Int {
        let patch = try supportedPatch(
            containing: target.sourceVertexIndex,
            in: polySpline,
            owner: owner
        )
        _ = patch
        return target.sourceVertexIndex
    }

    func validateTargetStillStable(
        _ target: PolySplineSurfaceVertexTarget,
        sourceVertexIndex: Int,
        in polySpline: PolySplineFeature,
        owner: String
    ) throws {
        guard target.sourceVertexIndex == sourceVertexIndex else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) would change the selected source vertex identity."
            )
        }
        let analysis = PolySplineMeshAnalyzer().analyze(
            mesh: polySpline.sourceMesh,
            options: polySpline.options,
            tolerance: tolerance
        )
        guard analysis.result.isSupported else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) would leave the source mesh unsupported: \(analysis.result.failureMessage ?? "No supported patch candidate.")"
            )
        }
        guard analysis.supportedPatches.contains(where: {
            $0.boundaryVertexIndices.contains(sourceVertexIndex)
        }) else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) would remove the selected vertex from every supported patch boundary."
            )
        }
    }

    func slideUnitVector(
        for target: PolySplineSurfaceVertexTarget,
        in polySpline: PolySplineFeature,
        direction: PolySplineSurfaceVertexSlideDirection
    ) throws -> Vector3D {
        let owner = "PolySpline surface vertex slide"
        let patch = try supportedPatch(
            containing: target.sourceVertexIndex,
            in: polySpline,
            owner: owner
        )
        guard let cornerIndex = patch.boundaryVertexIndices.firstIndex(
            of: target.sourceVertexIndex
        ),
        let corner = PolySplinePatchCorner(rawValue: cornerIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) requires an existing patch boundary vertex."
            )
        }

        func boundaryPoint(_ corner: PolySplinePatchCorner) throws -> Point3D {
            guard patch.boundaryVertexIndices.indices.contains(corner.rawValue) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(owner) requires an existing patch boundary vertex."
                )
            }
            let sourceVertexIndex = patch.boundaryVertexIndices[corner.rawValue]
            guard polySpline.sourceMesh.positions.indices.contains(sourceVertexIndex) else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "\(owner) references a missing source mesh vertex."
                )
            }
            return polySpline.sourceMesh.positions[sourceVertexIndex]
        }

        let positiveURaw: Vector3D
        switch corner {
        case .uMinVMin, .uMaxVMin:
            positiveURaw = try boundaryPoint(.uMaxVMin) - boundaryPoint(.uMinVMin)
        case .uMaxVMax, .uMinVMax:
            positiveURaw = try boundaryPoint(.uMaxVMax) - boundaryPoint(.uMinVMax)
        }

        let positiveVRaw: Vector3D
        switch corner {
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

    /// Shared corner vertices belong to more than one patch; the lowest
    /// candidate ID keeps the derived patch context deterministic.
    private func supportedPatch(
        containing sourceVertexIndex: Int,
        in polySpline: PolySplineFeature,
        owner: String
    ) throws -> PolySplineMeshAnalyzer.Analysis.SupportedPatch {
        let analysis = PolySplineMeshAnalyzer().analyze(
            mesh: polySpline.sourceMesh,
            options: polySpline.options,
            tolerance: tolerance
        )
        guard analysis.result.isSupported else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a supported PolySpline source mesh."
            )
        }
        let candidates = analysis.supportedPatches
            .filter { $0.boundaryVertexIndices.contains(sourceVertexIndex) }
            .sorted { $0.candidateID < $1.candidateID }
        guard let patch = candidates.first else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) requires an existing patch boundary vertex."
            )
        }
        return patch
    }

    private func normalizedSlideVector(
        _ vector: Vector3D,
        owner: String
    ) throws -> Vector3D {
        do {
            return try vector.normalized(tolerance: tolerance.distance)
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
