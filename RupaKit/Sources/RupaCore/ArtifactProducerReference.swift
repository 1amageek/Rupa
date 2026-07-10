import Foundation

public struct ArtifactProducerReference: Codable, Hashable, Sendable {
    public var id: String
    public var version: String

    public init(id: String, version: String) {
        self.id = id
        self.version = version
    }

    public func validate() throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReferenceValidationError(
                code: .invalidIdentity,
                message: "Artifact producers must contain an ID and version."
            )
        }
    }
}
