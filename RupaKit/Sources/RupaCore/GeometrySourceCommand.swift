import RupaCoreTypes

public enum GeometrySourceCommand: Codable, Equatable, Sendable {
    case editAuthoredMesh(AuthoredMeshEditCommand)
    case makeCADRepresentationEditable(MakeCADRepresentationEditableCommand)
    case selectRepresentation(GeometryRepresentationSelectionCommand)

    public var name: String {
        switch self {
        case .editAuthoredMesh(let edit):
            switch edit {
            case .setVertexPosition:
                "setAuthoredMeshVertexPosition"
            case .addFace:
                "addAuthoredMeshFace"
            case .deleteFace:
                "deleteAuthoredMeshFace"
            }
        case .makeCADRepresentationEditable:
            "makeCADRepresentationEditable"
        case .selectRepresentation:
            "selectGeometryRepresentation"
        }
    }

    public var requiredSourceRevision: DocumentTransactionRevision? {
        switch self {
        case .makeCADRepresentationEditable(let command):
            command.evaluationSnapshotID.sourceRevision
        case .editAuthoredMesh, .selectRepresentation:
            nil
        }
    }
}
