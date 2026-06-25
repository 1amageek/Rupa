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
        guard case .surface(.controlPoint(let reference)) = selection else {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface control point editing requires a surface control point selection reference."
            )
        }
        return try target(for: reference, in: document)
    }

    public func target(
        for reference: SurfaceControlPointReference,
        in document: DesignDocument
    ) throws -> SelectionTarget {
        do {
            try reference.validate()
        } catch {
            throw EditorError(
                code: .commandInvalid,
                message: "Surface control point editing requires a valid selection reference: \(error)."
            )
        }

        let patchFace = try polySplinePatchFace(from: reference.surface.faceName)
        let boundaryRole = try boundaryRole(uIndex: reference.uIndex, vIndex: reference.vIndex)
        guard let feature = document.cadDocument.designGraph.nodes[patchFace.featureID],
              case .polySpline = feature.operation else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "Surface control point editing requires an existing PolySpline source feature."
            )
        }
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
    ) throws -> PolySplineSurfaceVertexTarget.BoundaryRole {
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
            throw EditorError(
                code: .commandInvalid,
                message: "Surface control point editing currently supports PolySpline boundary corner control points only."
            )
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
