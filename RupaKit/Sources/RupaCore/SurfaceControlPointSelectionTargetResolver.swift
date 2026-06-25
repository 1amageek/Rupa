import SwiftCAD

public struct SurfaceControlPointSelectionTargetResolver: Sendable {
    private struct PolySplinePatchFace: Sendable {
        var featureID: FeatureID
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

        let patchFace = try polySplinePatchFace(from: reference.surface.faceName)
        guard let feature = document.cadDocument.designGraph.nodes[patchFace.featureID],
              case .polySpline = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface control point editing requires an existing PolySpline source feature."
            )
        }
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
                message: "Surface control point editing currently supports PolySpline corner and strict interior control points: \(error)."
            )
        }
        return .interiorControlPoint(PolySplineSurfaceControlPointEditTarget(
            featureID: patchFace.featureID,
            patchID: patchFace.patchID,
            uIndex: reference.uIndex,
            vIndex: reference.vIndex
        ))
    }

    private func boundaryTarget(
        patchFace: PolySplinePatchFace,
        boundaryRole: PolySplineSurfaceVertexTarget.BoundaryRole,
        in document: DesignDocument
    ) throws -> SelectionTarget {
        let sceneNodeID = try sceneNodeID(for: patchFace.featureID, in: document)
        let persistentName = persistentNameString(
            PersistentName(components: [
                .feature(patchFace.featureID),
                .generated("polySpline"),
                .subshape("patch:\(patchFace.patchID):vertex:\(boundaryRole.rawValue)"),
            ])
        )
        return SelectionTarget(
            sceneNodeID: sceneNodeID,
            component: .vertex(.generatedTopology(persistentName))
        )
    }

    private func polySplinePatchFace(from name: PersistentName) throws -> PolySplinePatchFace {
        var featureID: FeatureID?
        var generatedRole: String?
        var subshape: String?
        for component in name.components {
            switch component {
            case .feature(let id):
                featureID = id
            case .generated(let value):
                generatedRole = value
            case .subshape(let value):
                subshape = value
            case .index:
                throw invalidSurfaceReference()
            }
        }
        guard generatedRole == "polySpline",
              let featureID,
              let subshape else {
            throw invalidSurfaceReference()
        }
        let parts = subshape.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3,
              parts[0] == "patch",
              let patchID = Int(parts[1]),
              parts[2] == "face" else {
            throw invalidSurfaceReference()
        }
        return PolySplinePatchFace(featureID: featureID, patchID: patchID)
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

    private func persistentNameString(_ name: PersistentName) -> String {
        name.components.map { component in
            switch component {
            case .feature(let featureID):
                return "feature:\(featureID.description)"
            case .generated(let value):
                return "generated:\(value)"
            case .subshape(let value):
                return "subshape:\(value)"
            case .index(let index):
                return "index:\(index)"
            }
        }
        .joined(separator: "/")
    }

    private func invalidSurfaceReference() -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "Surface control point editing requires a PolySpline patch face selection reference."
        )
    }
}
