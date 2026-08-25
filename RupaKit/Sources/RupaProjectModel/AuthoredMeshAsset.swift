import RupaCoreTypes
import RupaGeometry

public struct AuthoredMeshAsset: Codable, Equatable, Sendable {
    public let source: MeshSource
    public let provenance: AuthoredMeshProvenance
    public let contentIdentity: ContentIdentity

    public var id: GeometrySourceID {
        source.identity
    }

    public init(
        source: MeshSource,
        provenance: AuthoredMeshProvenance
    ) throws {
        try source.validate()
        try provenance.validate()
        self.source = source
        self.provenance = provenance
        self.contentIdentity = try AuthoredMeshSourceIdentityService()
            .identityForValidatedSource(source)
    }

    public func validate() throws {
        try source.validate()
        try provenance.validate()
    }

    public func replacingSource(_ source: MeshSource) throws -> AuthoredMeshAsset {
        try AuthoredMeshAsset(source: source, provenance: provenance)
    }

    private enum CodingKeys: String, CodingKey {
        case source
        case provenance
        case contentIdentity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let source = try container.decode(MeshSource.self, forKey: .source)
        let provenance = try container.decode(AuthoredMeshProvenance.self, forKey: .provenance)
        let declaredIdentity = try container.decode(ContentIdentity.self, forKey: .contentIdentity)
        try self.init(source: source, provenance: provenance)
        guard declaredIdentity == contentIdentity else {
            throw DecodingError.dataCorruptedError(
                forKey: .contentIdentity,
                in: container,
                debugDescription: "Authored Mesh content identity does not match its source payload."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(source, forKey: .source)
        try container.encode(provenance, forKey: .provenance)
        try container.encode(contentIdentity, forKey: .contentIdentity)
    }
}
