import Foundation
import RupaCore

public struct DomainNamespaceRegistration: Sendable {
    public var namespace: SemanticNamespaceID
    public var supportedSchemaVersions: Set<SemanticSchemaVersion>

    public init(
        namespace: SemanticNamespaceID,
        supportedSchemaVersions: Set<SemanticSchemaVersion>
    ) {
        self.namespace = namespace
        self.supportedSchemaVersions = supportedSchemaVersions
    }

    public func validate() throws {
        try namespace.validate()
        guard !supportedSchemaVersions.isEmpty else {
            throw DomainRegistryError(
                code: .invalidRegistration,
                message: "Domain namespace registrations must declare supported schema versions."
            )
        }
        for version in supportedSchemaVersions {
            try version.validate()
        }
    }
}
