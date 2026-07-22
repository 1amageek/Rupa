import Foundation
import SwiftCAD
import RupaCoreTypes

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

    public static func canParse(subshapeID: SubshapeID) -> Bool {
        do {
            _ = try parse(subshapeID: subshapeID)
            return true
        } catch {
            return false
        }
    }

    public static func parse(componentID: SelectionComponentID) -> PolySplineSurfaceVertexTarget? {
        do {
            let reference = try componentID.stableTopologyReference(
                operationName: "PolySpline surface vertex"
            )
            return try parse(subshapeID: reference.subshapeID)
        } catch {
            return nil
        }
    }

    static func resolve(
        _ target: SelectionTarget,
        in document: DesignDocument
    ) throws -> PolySplineSurfaceVertexTarget {
        guard case .vertex(let componentID) = target.component else {
            throw EditorError(
                code: .commandInvalid,
                message: "PolySpline surface vertex move requires a generated topology vertex selection."
            )
        }
        let stableReference = try componentID.stableTopologyReference(
            operationName: "PolySpline surface vertex move"
        )
        let parsed = try parse(subshapeID: stableReference.subshapeID)
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

    private static func parse(
        subshapeID: SubshapeID
    ) throws -> PolySplineSurfaceVertexTarget {
        let prefix = "polySpline."
        guard subshapeID.role.hasPrefix(prefix),
              subshapeID.ordinal == 0 else {
            throw invalidStableReference()
        }
        let subshape = String(subshapeID.role.dropFirst(prefix.count))
        let parts = subshape.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 5,
              parts[0] == "patch",
              let patchID = Int(parts[1]),
              parts[2] == "vertex",
              let boundaryRole = BoundaryRole(rawValue: "\(parts[3]):\(parts[4])") else {
            throw invalidStableReference()
        }
        return PolySplineSurfaceVertexTarget(
            featureID: subshapeID.featureID,
            patchID: patchID,
            boundaryRole: boundaryRole
        )
    }

    private static func invalidStableReference() -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "PolySpline surface vertex move requires a stable PolySpline patch vertex reference."
        )
    }
}
