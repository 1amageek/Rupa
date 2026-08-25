import RupaCoreTypes

public enum AuthoredMeshProvenance: Codable, Hashable, Sendable {
    public static let cadSourceIdentityDomain = "rupa.cad-source"

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
        case .derivedFromCAD(let representationID, let sourceIdentity):
            do {
                try representationID.validate()
            } catch let error as EditorError {
                throw ProjectModelError(code: .invalidReference, message: error.message)
            }
            guard sourceIdentity.domain == Self.cadSourceIdentityDomain else {
                throw ProjectModelError(
                    code: .invalidReference,
                    message: "CAD-derived Authored Mesh provenance requires a CAD source content identity."
                )
            }
        }
    }
}
