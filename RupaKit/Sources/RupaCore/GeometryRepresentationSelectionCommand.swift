import RupaCoreTypes

public struct GeometryRepresentationSelectionCommand: Codable, Equatable, Sendable {
    public let sceneNodeID: SceneNodeID
    public let purpose: GeometryRepresentationPurpose
    public let representationID: GeometryRepresentationID

    public init(
        sceneNodeID: SceneNodeID,
        purpose: GeometryRepresentationPurpose,
        representationID: GeometryRepresentationID
    ) {
        self.sceneNodeID = sceneNodeID
        self.purpose = purpose
        self.representationID = representationID
    }

    public func validate() throws {
        try representationID.validate()
    }
}
