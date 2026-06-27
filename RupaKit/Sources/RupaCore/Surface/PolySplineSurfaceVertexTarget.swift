import Foundation
import SwiftCAD

public struct PolySplineSurfaceVertexTarget: Equatable, Hashable, Sendable {
    public enum BoundaryRole: String, Equatable, Hashable, Sendable {
        case uMinVMin = "uMin:vMin"
        case uMaxVMin = "uMax:vMin"
        case uMaxVMax = "uMax:vMax"
        case uMinVMax = "uMin:vMax"

        public var boundaryIndex: Int {
            switch self {
            case .uMinVMin:
                0
            case .uMaxVMin:
                1
            case .uMaxVMax:
                2
            case .uMinVMax:
                3
            }
        }
    }

    public var featureID: FeatureID
    public var patchID: Int
    public var boundaryRole: BoundaryRole

    public init(
        featureID: FeatureID,
        patchID: Int,
        boundaryRole: BoundaryRole
    ) {
        self.featureID = featureID
        self.patchID = patchID
        self.boundaryRole = boundaryRole
    }

    public static func canParsePersistentName(_ persistentName: String) -> Bool {
        do {
            _ = try parsePersistentName(persistentName)
            return true
        } catch {
            return false
        }
    }

    public static func parse(componentID: SelectionComponentID) -> PolySplineSurfaceVertexTarget? {
        guard let persistentName = componentID.generatedTopologyPersistentName else {
            return nil
        }
        do {
            return try parsePersistentName(persistentName)
        } catch {
            return nil
        }
    }

    static func resolve(
        _ target: SelectionTarget,
        in document: DesignDocument
    ) throws -> PolySplineSurfaceVertexTarget {
        guard case .vertex(let componentID) = target.component,
              let persistentName = componentID.generatedTopologyPersistentName else {
            throw EditorError(
                code: .commandInvalid,
                message: "PolySpline surface vertex move requires a generated topology vertex selection."
            )
        }
        let parsed = try parsePersistentName(persistentName)
        guard let sceneNode = document.productMetadata.sceneNodes[target.sceneNodeID] else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "PolySpline surface vertex move requires an existing scene node."
            )
        }
        guard sceneNode.reference?.featureID == parsed.featureID else {
            throw EditorError(
                code: .referenceUnresolved,
                message: "PolySpline surface vertex selection does not belong to the target scene node."
            )
        }
        guard let feature = document.cadDocument.designGraph.nodes[parsed.featureID],
              case .polySpline = feature.operation else {
            throw EditorError(
                code: .commandInvalid,
                message: "PolySpline surface vertex move requires a PolySpline source feature."
            )
        }
        return parsed
    }

    private static func parsePersistentName(_ persistentName: String) throws -> PolySplineSurfaceVertexTarget {
        var featureID: FeatureID?
        var generatedRole: String?
        var subshape: String?
        for component in persistentName.split(separator: "/", omittingEmptySubsequences: false) {
            let text = String(component)
            if text.hasPrefix("feature:") {
                let uuidText = String(text.dropFirst("feature:".count))
                guard let uuid = UUID(uuidString: uuidText) else {
                    throw invalidPersistentName()
                }
                featureID = FeatureID(uuid)
            } else if text.hasPrefix("generated:") {
                generatedRole = String(text.dropFirst("generated:".count))
            } else if text.hasPrefix("subshape:") {
                subshape = String(text.dropFirst("subshape:".count))
            }
        }
        guard generatedRole == "polySpline",
              let featureID,
              let subshape else {
            throw invalidPersistentName()
        }
        let parts = subshape.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5,
              parts[0] == "patch",
              let patchID = Int(parts[1]),
              parts[2] == "vertex",
              let boundaryRole = BoundaryRole(rawValue: "\(parts[3]):\(parts[4])") else {
            throw invalidPersistentName()
        }
        return PolySplineSurfaceVertexTarget(
            featureID: featureID,
            patchID: patchID,
            boundaryRole: boundaryRole
        )
    }

    private static func invalidPersistentName() -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "PolySpline surface vertex move requires a PolySpline patch vertex persistent name."
        )
    }
}
