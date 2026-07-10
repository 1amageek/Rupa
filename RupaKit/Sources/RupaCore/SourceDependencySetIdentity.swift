import RupaCoreTypes

public struct SourceDependencySetIdentity: Codable, Hashable, Sendable {
    public let dependencies: [SourceDependencyIdentity]
    public let fingerprint: ContentFingerprint

    public init(dependencies: [SourceDependencyIdentity]) throws {
        let dependencies = dependencies.sorted { $0.subject.sortKey < $1.subject.sortKey }
        guard !dependencies.isEmpty else {
            throw ReferenceValidationError(
                code: .invalidShape,
                message: "Source dependency sets must not be empty."
            )
        }
        guard Set(dependencies.map(\.subject)).count == dependencies.count else {
            throw ReferenceValidationError(
                code: .invalidIdentity,
                message: "Source dependency sets must contain each logical subject exactly once."
            )
        }
        self.dependencies = dependencies
        var hasher = CanonicalIdentityHasher(domain: "source-dependency-set.v1")
        hasher.appendField("dependencies")
        hasher.appendCount(dependencies.count)
        for dependency in dependencies {
            dependency.appendCanonicalIdentity(to: &hasher)
        }
        self.fingerprint = try hasher.fingerprint(
            algorithm: "sha256-source-dependency-set-v1"
        )
    }

    private enum CodingKeys: String, CodingKey {
        case dependencies
        case fingerprint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let encodedFingerprint = try container.decode(ContentFingerprint.self, forKey: .fingerprint)
        try self.init(
            dependencies: container.decode([SourceDependencyIdentity].self, forKey: .dependencies)
        )
        guard fingerprint == encodedFingerprint else {
            throw ReferenceValidationError(
                code: .invalidIdentity,
                message: "Source dependency set fingerprint does not match its dependencies."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(dependencies, forKey: .dependencies)
        try container.encode(fingerprint, forKey: .fingerprint)
    }
}
