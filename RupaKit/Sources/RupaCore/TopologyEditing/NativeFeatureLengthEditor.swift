import SwiftCAD
import RupaCoreTypes

public struct NativeFeatureLengthEditor: FeatureLengthEditing {
    public init() {}

    public func length(in operation: FeatureOperation) -> FeatureLengthDefinition? {
        switch operation {
        case .extrude(let value): .init(title: "Distance", expression: value.distance)
        case .fillet(let value): .init(title: "Radius", expression: value.radius)
        case .chamfer(let value): .init(title: "Distance", expression: value.distance)
        case .g2Blend(let value): .init(title: "Distance", expression: value.distance)
        case .shell(let value): .init(title: "Wall thickness", expression: value.thickness)
        case .thicken(let value): .init(title: "Thickness", expression: value.thickness)
        case .surfaceOffset(let value): .init(title: "Signed normal offset", expression: value.distance)
        default: nil
        }
    }

    public func replacingLength(in operation: FeatureOperation, with expression: CADExpression) throws -> FeatureOperation {
        switch operation {
        case .extrude(var value):
            value.distance = expression
            return .extrude(value)
        case .fillet(let value):
            return .fillet(.init(target: value.target, edges: value.edges, radius: expression, allEdges: value.allEdges))
        case .chamfer(let value):
            return .chamfer(.init(target: value.target, edges: value.edges, distance: expression))
        case .g2Blend(let value):
            return .g2Blend(.init(target: value.target, edges: value.edges, distance: expression))
        case .shell(let value):
            return .shell(.init(target: value.target, removedFaces: value.removedFaces, thickness: expression))
        case .thicken(let value):
            return .thicken(.init(target: value.target, thickness: expression, side: value.side))
        case .surfaceOffset(let value):
            return .surfaceOffset(.init(target: value.target, distance: expression))
        default:
            throw EditorError(code: .commandInvalid, message: "This feature has no editable native length.")
        }
    }
}
