import Foundation
import SwiftCAD
import RupaCoreTypes

extension DesignDocument {
    func editableBodyFace(
        for target: SelectionTarget,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> EditableBodyFace {
        guard case .face(let componentID) = target.component else {
            throw EditorError(
                code: .commandInvalid,
                message: "Face offset requires a face selection target."
            )
        }
        if componentID.isStableTopology {
            let bodyFace = try GeneratedTopologySelectionResolver().bodyFace(
                for: target,
                in: self,
                objectRegistry: objectRegistry,
                operationName: "Face offset"
            )
            return editableBodyFace(for: bodyFace)
        }
        switch componentID {
        case .bodyFaceFront:
            return .front
        case .bodyFaceBack:
            return .back
        case .bodyFaceTop:
            return .top
        case .bodyFaceBottom:
            return .bottom
        case .bodyFaceLeft:
            return .left
        case .bodyFaceRight:
            return .right
        case .bodyFaceSide:
            return .side
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "Face offset target is not an editable body face."
            )
        }
    }

    func editableBodyFace(for bodyFace: BodyFace) -> EditableBodyFace {
        switch bodyFace {
        case .front:
            return .front
        case .back:
            return .back
        case .top:
            return .top
        case .bottom:
            return .bottom
        case .left:
            return .left
        case .right:
            return .right
        case .side:
            return .side
        }
    }

    func editableBodyEdge(
        for target: SelectionTarget,
        operationName: String = "Edge chamfer",
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> EditableBodyEdge {
        guard case .edge(let componentID) = target.component else {
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) requires edge selection targets."
            )
        }
        if componentID.isStableTopology {
            let cornerEdge = try GeneratedTopologySelectionResolver().cornerEdge(
                for: target,
                in: self,
                objectRegistry: objectRegistry,
                operationName: operationName
            )
            return editableBodyEdge(for: cornerEdge)
        }
        switch componentID {
        case .bodyEdgeLeftBottom:
            return .leftBottom
        case .bodyEdgeRightBottom:
            return .rightBottom
        case .bodyEdgeRightTop:
            return .rightTop
        case .bodyEdgeLeftTop:
            return .leftTop
        default:
            throw EditorError(
                code: .commandInvalid,
                message: "\(operationName) target is not an editable body edge."
            )
        }
    }

    func editableBodyEdge(for cornerEdge: BodyCornerEdge) -> EditableBodyEdge {
        switch cornerEdge {
        case .leftBottom:
            return .leftBottom
        case .rightBottom:
            return .rightBottom
        case .rightTop:
            return .rightTop
        case .leftTop:
            return .leftTop
        }
    }

    func editableBodyVertex(
        for target: SelectionTarget,
        objectRegistry: ObjectTypeRegistry = .builtIn
    ) throws -> EditableBodyVertex {
        guard case .vertex(let componentID) = target.component else {
            throw EditorError(
                code: .commandInvalid,
                message: "Vertex move requires a vertex selection target."
            )
        }
        if componentID.isStableTopology {
            let cornerVertex = try GeneratedTopologySelectionResolver().cornerVertex(
                for: target,
                in: self,
                objectRegistry: objectRegistry,
                operationName: "Vertex move"
            )
            return editableBodyVertex(for: cornerVertex)
        }
        throw EditorError(
            code: .commandInvalid,
            message: "Vertex move target is not an editable generated body vertex."
        )
    }

    func editableBodyVertex(for cornerVertex: BodyCornerVertex) -> EditableBodyVertex {
        switch cornerVertex {
        case .frontBottomLeft, .backBottomLeft:
            return .bottomLeft
        case .frontBottomRight, .backBottomRight:
            return .bottomRight
        case .frontTopRight, .backTopRight:
            return .topRight
        case .frontTopLeft, .backTopLeft:
            return .topLeft
        }
    }
}
