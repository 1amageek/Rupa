public struct ContentIdentity: Codable, Hashable, Sendable {
    public let domain: String
    public let fingerprint: ContentFingerprint

    public init(domain: String, fingerprint: ContentFingerprint) throws {
        try StableTypeValidation.validateIdentifier(
            domain,
            name: "Content identity domains",
            requiresQualifiedName: true
        )
        self.domain = domain
        self.fingerprint = fingerprint
    }

    private enum CodingKeys: String, CodingKey {
        case domain
        case fingerprint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            domain: container.decode(String.self, forKey: .domain),
            fingerprint: container.decode(ContentFingerprint.self, forKey: .fingerprint)
        )
    }
}
