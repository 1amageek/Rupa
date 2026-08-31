import RupaDomainFoundation

public struct AgentSemanticSchemaVersion: Codable, Equatable, Sendable {
    public let major: UInt32
    public let minor: UInt32
    public let patch: UInt32

    private enum CodingKeys: String, CodingKey {
        case major
        case minor
        case patch
    }

    public init(major: UInt32, minor: UInt32, patch: UInt32) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init(_ value: SemanticProgramSchemaVersion) {
        self.init(major: value.major, minor: value.minor, patch: value.patch)
    }

    public var semanticValue: SemanticProgramSchemaVersion {
        SemanticProgramSchemaVersion(major: major, minor: minor, patch: patch)
    }

    public init(from decoder: Decoder) throws {
        try AgentSemanticCoding.rejectUnknownKeys(
            from: decoder,
            allowedKeys: ["major", "minor", "patch"]
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            major: try container.decode(UInt32.self, forKey: .major),
            minor: try container.decode(UInt32.self, forKey: .minor),
            patch: try container.decode(UInt32.self, forKey: .patch)
        )
    }
}
