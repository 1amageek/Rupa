import SwiftCAD

/// The original incidence authority of one current B-rep body.
public struct OriginalBodyTopologyMembership: Sendable {
    private let references: Set<TopologyReference>

    public init(bodyID: BodyID, in model: BRepModel) throws {
        guard let body = model.bodies[bodyID] else {
            throw EditorError(code: .referenceUnresolved, message: "Original selected body is missing.")
        }
        var owned: Set<TopologyReference> = [.body(bodyID)]
        for shellID in body.shellIDs {
            try Task.checkCancellation()
            guard let shell = model.shells[shellID] else {
                throw EditorError(code: .referenceUnresolved, message: "Original selected body shell is missing.")
            }
            for faceID in shell.faceIDs {
                owned.insert(.face(faceID))
                guard let face = model.faces[faceID] else {
                    throw EditorError(code: .referenceUnresolved, message: "Original selected body face is missing.")
                }
                for loopID in face.loops {
                    guard let loop = model.loops[loopID] else {
                        throw EditorError(code: .referenceUnresolved, message: "Original selected body loop is missing.")
                    }
                    for coedge in loop.coedges {
                        owned.insert(.edge(coedge.edgeID))
                        guard let edge = model.edges[coedge.edgeID],
                              model.vertices[edge.startVertexID] != nil, model.vertices[edge.endVertexID] != nil else {
                            throw EditorError(code: .referenceUnresolved, message: "Original selected body edge or endpoint is missing.")
                        }
                        owned.insert(.vertex(edge.startVertexID)); owned.insert(.vertex(edge.endVertexID))
                    }
                }
            }
        }
        references = owned
    }

    public func contains(_ reference: TopologyReference) -> Bool { references.contains(reference) }
    public static func validate(_ target: SelectionTarget, in evaluated: EvaluatedDocument?) throws {
        guard let bodyID = target.sourceBodyID else { return }
        guard let evaluated, let featureID = target.sourceFeatureID,
              evaluated.subshapes.entries.contains(where: { $0.key.featureID == featureID && $0.value == .body(bodyID) }) else {
            throw EditorError(code: .referenceUnresolved, message: "Selection body witness is absent from the original evaluation.")
        }
        let component: SelectionComponentID
        switch target.component {
        case .face(let id), .edge(let id), .vertex(let id): component = id
        case .object: return
        default:
            throw EditorError(code: .referenceUnresolved, message: "Body-bound selection names no original body topology.")
        }
        guard let identity = component.generatedTopologySubshapeID, identity.featureID == featureID,
              let reference = evaluated.subshapes.entries[identity],
              try OriginalBodyTopologyMembership(bodyID: bodyID, in: evaluated.brep).contains(reference) else {
            throw EditorError(code: .referenceUnresolved, message: "Selection subshape is outside its original body.")
        }
        switch (target.component, reference) {
        case (.face, .face), (.edge, .edge), (.vertex, .vertex): break
        default: throw EditorError(code: .referenceUnresolved, message: "Selection component and original topology kind differ.")
        }
    }

}
