import RupaCoreTypes

public enum AuthoredMeshProvenance: Codable, Hashable, Sendable {
    case created
    case imported(ContentIdentity)
    case derivedFromCAD(
        representationID: GeometryRepresentationID,
        sourceIdentity: ContentIdentity
    )

    public func validate() throws {
        switch self {
        case .created, .imported:
            return
        case .derivedFromCAD(let representationID, _):
            do {
                try representationID.validate()
            } catch let error as EditorError {
                throw ProjectModelError(code: .invalidReference, message: error.message)
            }
        }
    }
}
