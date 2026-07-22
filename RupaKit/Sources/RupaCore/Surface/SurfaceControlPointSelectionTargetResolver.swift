import CADModeling
import SwiftCAD
import RupaCoreTypes

public struct SurfaceControlPointSelectionTargetResolver: Sendable {
    private struct SurfacePatchFace: Sendable {
        var featureID: FeatureID
        var generatedRole: String
        var patchID: Int
    }

    public init() {}

    public func target(
        for selection: SelectionReference,
        in document: DesignDocument
    ) throws -> SelectionTarget {
        guard case .boundaryVertex(let target) = try editTarget(for: selection, in: document) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface control point boundary vertex editing requires a corner control point selection reference."
            )
        }
        return target
    }

    public func editTarget(
        for selection: SelectionReference,
        in document: DesignDocument
    ) throws -> SurfaceControlPointEditTarget {
        guard case .surface(.controlPoint(let reference)) = selection else {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface control point editing requires a surface control point selection reference."
            )
        }
        return try editTarget(for: reference, in: document)
    }

    public func validateDisplayTarget(
        for selection: SelectionReference,
        in document: DesignDocument
    ) throws -> SurfaceControlPointReference {
        try validateDisplayTarget(
            for: selection,
            in: document.cadDocument,
            tolerance: document.modelingSettings.tolerance
        )
    }

    public func validateDisplayTarget(
        for selection: SelectionReference,
        in cadDocument: CADDocument,
        tolerance: ModelingTolerance
    ) throws -> SurfaceControlPointReference {
        guard case .surface(.controlPoint(let reference)) = selection else {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface control point display requires a surface control point selection reference."
            )
        }
        try validateDisplayTarget(
            for: reference,
            in: cadDocument,
            tolerance: tolerance
        )
        return reference
    }

    public func target(
        for reference: SurfaceControlPointReference,
        in document: DesignDocument
    ) throws -> SelectionTarget {
        guard case .boundaryVertex(let target) = try editTarget(for: reference, in: document) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface control point boundary vertex editing requires a corner control point selection reference."
            )
        }
        return target
    }

    public func editTarget(
        for reference: SurfaceControlPointReference,
        in document: DesignDocument
    ) throws -> SurfaceControlPointEditTarget {
        do {
            try reference.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface control point editing requires a valid selection reference: \(error)."
            )
        }

        let patchFace = try surfacePatchFace(from: reference.surface.subshape)
        guard let feature = document.cadDocument.designGraph.nodes[patchFace.featureID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface control point editing requires an existing editable surface source feature."
            )
        }
        switch feature.operation {
        case .polySpline:
            return try polySplineEditTarget(
                for: reference,
                patchFace: patchFace,
                in: document
            )
        case .bSplineSurface(let surfaceFeature):
            try validateBSplineSurfacePatchFace(
                patchFace,
                owner: "Surface control point editing"
            )
            try validateBSplineSurfaceControlPoint(
                reference,
                in: surfaceFeature,
                owner: "Surface control point editing"
            )
            return .bSplineSurfaceControlPoint(BSplineSurfaceControlPointEditTarget(
                featureID: patchFace.featureID,
                uIndex: reference.uIndex,
                vIndex: reference.vIndex
            ))
        default:
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface control point editing requires an existing editable surface source feature."
            )
        }
    }

    private func validateDisplayTarget(
        for reference: SurfaceControlPointReference,
        in cadDocument: CADDocument,
        tolerance: ModelingTolerance
    ) throws {
        do {
            try reference.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface control point display requires a valid selection reference: \(error)."
            )
        }
        let patchFace = try surfacePatchFace(from: reference.surface.subshape)
        guard let feature = cadDocument.designGraph.nodes[patchFace.featureID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface control point display requires an existing editable surface source feature."
            )
        }
        switch feature.operation {
        case .polySpline(let polySpline):
            try validatePolySplineDisplayTarget(
                reference,
                patchFace: patchFace,
                polySpline: polySpline,
                tolerance: tolerance
            )
        case .bSplineSurface(let surfaceFeature):
            try validateBSplineSurfacePatchFace(
                patchFace,
                owner: "Surface control point display"
            )
            try validateBSplineSurfaceControlPoint(
                reference,
                in: surfaceFeature,
                owner: "Surface control point display"
            )
        default:
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface control point display requires an existing editable surface source feature."
            )
        }
    }

    private func polySplineEditTarget(
        for reference: SurfaceControlPointReference,
        patchFace: SurfacePatchFace,
        in document: DesignDocument
    ) throws -> SurfaceControlPointEditTarget {
        try validatePolySplinePatchFace(
            patchFace,
            owner: "Surface control point editing"
        )
        if let boundaryRole = boundaryRole(uIndex: reference.uIndex, vIndex: reference.vIndex) {
            return .boundaryVertex(try boundaryTarget(
                patchFace: patchFace,
                boundaryRole: boundaryRole,
                in: document
            ))
        }
        let address = PolySplineSurfaceControlPointAddress(
            patchID: patchFace.patchID,
            uIndex: reference.uIndex,
            vIndex: reference.vIndex
        )
        do {
            try address.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface control point editing supports PolySpline corner and strict interior control points: \(error)."
            )
        }
        return .interiorControlPoint(PolySplineSurfaceControlPointEditTarget(
            featureID: patchFace.featureID,
            patchID: patchFace.patchID,
            uIndex: reference.uIndex,
            vIndex: reference.vIndex
        ))
    }

    private func validatePolySplineDisplayTarget(
        _ reference: SurfaceControlPointReference,
        patchFace: SurfacePatchFace,
        polySpline: PolySplineFeature,
        tolerance: ModelingTolerance
    ) throws {
        try validatePolySplinePatchFace(
            patchFace,
            owner: "Surface control point display"
        )
        guard (0 ... 3).contains(reference.uIndex),
              (0 ... 3).contains(reference.vIndex) else {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface control point display supports PolySpline patch control point indexes from 0 through 3."
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
                message: "Surface control point display requires a supported PolySpline source mesh."
            )
        }
        guard analysis.supportedPatches.contains(where: { $0.candidateID == patchFace.patchID }) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface control point display requires an existing PolySpline patch target."
            )
        }
    }

    private func validateBSplineSurfaceControlPoint(
        _ reference: SurfaceControlPointReference,
        in surfaceFeature: BSplineSurfaceFeature,
        owner: String
    ) throws {
        guard surfaceFeature.surface.controlPoints.indices.contains(reference.vIndex),
              surfaceFeature.surface.controlPoints[reference.vIndex].indices.contains(reference.uIndex),
              surfaceFeature.surface.weights.indices.contains(reference.vIndex),
              surfaceFeature.surface.weights[reference.vIndex].indices.contains(reference.uIndex) else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "\(owner) references a missing B-spline surface control point."
            )
        }
    }

    private func validatePolySplinePatchFace(
        _ patchFace: SurfacePatchFace,
        owner: String
    ) throws {
        guard patchFace.generatedRole == "polySpline" else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a PolySpline patch face selection reference."
            )
        }
    }

    private func validateBSplineSurfacePatchFace(
        _ patchFace: SurfacePatchFace,
        owner: String
    ) throws {
        guard patchFace.generatedRole == "bSplineSurface",
              patchFace.patchID == 0 else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(owner) requires a direct B-spline surface patch face selection reference."
            )
        }
    }

    private func boundaryTarget(
        patchFace: SurfacePatchFace,
        boundaryRole: PolySplineSurfaceVertexTarget.BoundaryRole,
        in document: DesignDocument
    ) throws -> SelectionTarget {
        let sceneNodeID = try sceneNodeID(for: patchFace.featureID, in: document)
        let evaluatedDocument = try DocumentEvaluationContextResolver().evaluatedDocument(
            document: document,
            failurePrefix: "Surface control point editing requires current PolySpline topology"
        )
        let subshapeID = SubshapeID(
            featureID: patchFace.featureID,
            role: "polySpline.patch:\(patchFace.patchID):vertex:\(boundaryRole.rawValue)",
            ordinal: 0
        )
        let stableReference = try evaluatedDocument.stableSubshapeReference(for: subshapeID)
        return SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .vertex(try .stableTopology(stableReference))
        )
    }

    private func surfacePatchFace(
        from reference: StableSubshapeReference
    ) throws -> SurfacePatchFace {
        let subshapeID = reference.subshapeID
        guard subshapeID.ordinal == 0 else {
            throw invalidSurfaceReference()
        }
        let roleParts = subshapeID.role.split(
            separator: ".",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).map(String.init)
        guard roleParts.count == 2 else {
            throw invalidSurfaceReference()
        }
        let parts = roleParts[1].split(
            separator: ":",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard parts.count == 3,
              parts[0] == "patch",
              let patchID = Int(parts[1]),
              parts[2] == "face" else {
            throw invalidSurfaceReference()
        }
        return SurfacePatchFace(
            featureID: subshapeID.featureID,
            generatedRole: roleParts[0],
            patchID: patchID
        )
    }

    private func boundaryRole(
        uIndex: Int,
        vIndex: Int
    ) -> PolySplineSurfaceVertexTarget.BoundaryRole? {
        switch (uIndex, vIndex) {
        case (0, 0):
            .uMinVMin
        case (3, 0):
            .uMaxVMin
        case (3, 3):
            .uMaxVMax
        case (0, 3):
            .uMinVMax
        default:
            nil
        }
    }

    private func sceneNodeID(
        for featureID: FeatureID,
        in document: DesignDocument
    ) throws -> SceneNodeID {
        let candidates = document.productMetadata.sceneNodes.values
            .filter { $0.reference?.featureID == featureID }
            .sorted { $0.id.description < $1.id.description }
        guard let sceneNode = candidates.first else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface control point editing requires a scene node for the PolySpline source feature."
            )
        }
        return sceneNode.id
    }

    private func invalidSurfaceReference() -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "Surface control point editing requires a source-owned surface patch face selection reference."
        )
    }
}
