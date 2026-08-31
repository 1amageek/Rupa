import RupaCoreTypes

public struct AgentSemanticOperationVersion: Codable, Equatable, Sendable {
    public let major: UInt32
    public let minor: UInt32
    public let patch: UInt32

    private enum CodingKeys: String, CodingKey { case major, minor, patch }

    public init(major: UInt32, minor: UInt32, patch: UInt32) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public init(_ value: CapabilityVersion) {
        self.init(major: value.major, minor: value.minor, patch: value.patch)
    }

    public var semanticValue: CapabilityVersion {
        CapabilityVersion(major: major, minor: minor, patch: patch)
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
