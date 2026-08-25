import RupaCoreTypes

public struct GeometryRepresentation: Codable, Hashable, Sendable {
    public var id: GeometryRepresentationID
    public var source: GeometrySourceReference

    public init(
        id: GeometryRepresentationID,
        source: GeometrySourceReference
    ) {
        self.id = id
        self.source = source
    }

    public func validate() throws {
        do {
            try id.validate()
        } catch let error as EditorError {
            throw ProjectModelError(code: .invalidIdentity, message: error.message)
        }
        try source.validate()
    }
}
