public enum GeometrySourceCommand: Codable, Equatable, Sendable {
    case editAuthoredMesh(AuthoredMeshEditCommand)
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
        case .selectRepresentation:
            "selectGeometryRepresentation"
        }
    }
}
