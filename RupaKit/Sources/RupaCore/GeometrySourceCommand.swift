import RupaCoreTypes

public enum GeometrySourceCommand: Codable, Equatable, Sendable {
    case editAuthoredMesh(AuthoredMeshEditCommand)
    case importAuthoredMesh(ImportAuthoredMeshCommand)
    case makeCADRepresentationEditable(MakeCADRepresentationEditableCommand)
    case selectRepresentation(GeometryRepresentationSelectionCommand)

    public var name: String {
        switch self {
        case .editAuthoredMesh:
            "editAuthoredMesh"
        case .importAuthoredMesh:
            "importAuthoredMesh"
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
        case .editAuthoredMesh, .importAuthoredMesh, .selectRepresentation:
            nil
        }
    }
}
