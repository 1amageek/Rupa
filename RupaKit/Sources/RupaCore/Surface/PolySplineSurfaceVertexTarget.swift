import Foundation
import SwiftCAD
import RupaCoreTypes

/// Identity of an editable PolySpline boundary vertex.
///
/// The kernel names PolySpline vertices by their source-mesh index
/// (`polySpline.vertex:source:<index>`), so the product identity is the owning
/// feature plus that source index. Patch context (corner roles, slide
/// directions) is re-derived from the current mesh analysis instead of being
/// baked into the identity.
public struct PolySplineSurfaceVertexTarget: Equatable, Hashable, Sendable {
    public var featureID: FeatureID
    public var sourceVertexIndex: Int

    public init(
        featureID: FeatureID,
        sourceVertexIndex: Int
    ) {
        self.featureID = featureID
        self.sourceVertexIndex = sourceVertexIndex
    }

    public static func canParse(subshapeID: SubshapeID) -> Bool {
        parse(subshapeID: subshapeID) != nil
    }

    public static func parse(componentID: SelectionComponentID) -> PolySplineSurfaceVertexTarget? {
        guard let subshapeID = componentID.generatedTopologySubshapeID else {
            return nil
        }
        return parse(subshapeID: subshapeID)
    }

    public static func parse(subshapeID: SubshapeID) -> PolySplineSurfaceVertexTarget? {
        let roleParts = subshapeID.role.split(
            separator: ".",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).map(String.init)
        guard roleParts.count == 2,
              roleParts[0] == "polySpline" else {
            return nil
        }
        let vertexParts = roleParts[1].split(
            separator: ":",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard vertexParts.count == 3,
              vertexParts[0] == "vertex",
              vertexParts[1] == "source",
              let sourceVertexIndex = Int(vertexParts[2]),
              sourceVertexIndex >= 0 else {
            return nil
        }
        return PolySplineSurfaceVertexTarget(
            featureID: subshapeID.featureID,
            sourceVertexIndex: sourceVertexIndex
        )
    }

    static func resolve(
        _ target: SelectionTarget,
        in document: DesignDocument
    ) throws -> PolySplineSurfaceVertexTarget {
        guard case .vertex(let componentID) = target.component,
              let subshapeID = componentID.generatedTopologySubshapeID,
              let parsed = parse(subshapeID: subshapeID) else {
            throw EditorError(
                code: .commandInvalid,
                message: "PolySpline surface vertex move requires a generated topology vertex selection."
            )
        }
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
}

/// Corner position of a boundary vertex inside one supported patch, in the
/// analyzer's `boundaryVertexIndices` order.
enum PolySplinePatchCorner: Int, CaseIterable, Sendable {
    case uMinVMin = 0
    case uMaxVMin = 1
    case uMaxVMax = 2
    case uMinVMax = 3
}
