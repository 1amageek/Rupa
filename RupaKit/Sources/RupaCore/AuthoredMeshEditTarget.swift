import RupaCoreTypes
import RupaProjectModel

/// Identifies the retained Authored Mesh source that a plan is allowed to edit.
///
/// Scene and representation coordinates are intentionally absent. They select
/// or navigate a Product Object, but they do not establish source authority.
public struct AuthoredMeshEditTarget: Codable, Equatable, Sendable {
    public let sourceID: GeometrySourceID
    public let expectedSourceIdentity: ContentIdentity

    public init(
        sourceID: GeometrySourceID,
        expectedSourceIdentity: ContentIdentity
    ) {
        self.sourceID = sourceID
        self.expectedSourceIdentity = expectedSourceIdentity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.sceneNodeID) {
            throw DecodingError.dataCorruptedError(
                forKey: .sceneNodeID,
                in: container,
                debugDescription: "Authored Mesh edit targets no longer accept scene-node coordinates."
            )
        }
        if container.contains(.representationID) {
            throw DecodingError.dataCorruptedError(
                forKey: .representationID,
                in: container,
                debugDescription: "Authored Mesh edit targets no longer accept representation coordinates."
            )
        }
        self.init(
            sourceID: try container.decode(GeometrySourceID.self, forKey: .sourceID),
            expectedSourceIdentity: try container.decode(
                ContentIdentity.self,
                forKey: .expectedSourceIdentity
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sourceID, forKey: .sourceID)
        try container.encode(expectedSourceIdentity, forKey: .expectedSourceIdentity)
    }

    public func validate() throws {
        try sourceID.validate()
        guard expectedSourceIdentity.domain == AuthoredMeshSourceIdentityService.domain else {
            throw EditorError(
                code: .commandInvalid,
                message: "Authored Mesh edit targets require an Authored Mesh source content identity."
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case sourceID
        case expectedSourceIdentity
        case sceneNodeID
        case representationID
    }
}
