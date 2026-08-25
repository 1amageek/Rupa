import RupaCoreTypes
import RupaProjectModel

public struct AuthoredMeshEditTarget: Codable, Equatable, Sendable {
    public let sceneNodeID: SceneNodeID
    public let representationID: GeometryRepresentationID
    public let sourceID: GeometrySourceID
    public let expectedSourceIdentity: ContentIdentity

    public init(
        sceneNodeID: SceneNodeID,
        representationID: GeometryRepresentationID,
        sourceID: GeometrySourceID,
        expectedSourceIdentity: ContentIdentity
    ) {
        self.sceneNodeID = sceneNodeID
        self.representationID = representationID
        self.sourceID = sourceID
        self.expectedSourceIdentity = expectedSourceIdentity
    }

    public func validate() throws {
        try representationID.validate()
        try sourceID.validate()
        guard expectedSourceIdentity.domain == AuthoredMeshSourceIdentityService.domain else {
            throw EditorError(
                code: .commandInvalid,
                message: "Authored Mesh edit targets require an Authored Mesh source content identity."
            )
        }
    }
}
