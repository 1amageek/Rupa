import SwiftCAD
import RupaCoreTypes

public struct MaterializedArtifactReference: Codable, Hashable, Sendable {
    public let computation: ArtifactComputationIdentity
    public let contentFingerprint: ContentFingerprint
    public let fingerprint: ContentFingerprint

    public init(
        computation: ArtifactComputationIdentity,
        contentFingerprint: ContentFingerprint
    ) throws {
        self.computation = computation
        self.contentFingerprint = contentFingerprint
        var hasher = CanonicalIdentityHasher(domain: "materialized-artifact.v1")
        hasher.appendField("computation")
        hasher.appendString(computation.fingerprint.algorithm)
        hasher.appendString(computation.fingerprint.value)
        hasher.appendField("content")
        hasher.appendString(contentFingerprint.algorithm)
        hasher.appendString(contentFingerprint.value)
        self.fingerprint = try hasher.fingerprint(
            algorithm: "sha256-materialized-artifact-v1"
        )
    }

    public var documentID: DocumentID {
        computation.documentID
    }

    public var kind: DerivedArtifactKind {
        computation.kind
    }

    private enum CodingKeys: String, CodingKey {
        case computation
        case contentFingerprint
        case fingerprint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let encodedFingerprint = try container.decode(ContentFingerprint.self, forKey: .fingerprint)
        try self.init(
            computation: container.decode(ArtifactComputationIdentity.self, forKey: .computation),
            contentFingerprint: container.decode(ContentFingerprint.self, forKey: .contentFingerprint)
        )
        guard fingerprint == encodedFingerprint else {
            throw ReferenceValidationError(
                code: .invalidIdentity,
                message: "Materialized artifact fingerprint does not match its computation and content."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(computation, forKey: .computation)
        try container.encode(contentFingerprint, forKey: .contentFingerprint)
        try container.encode(fingerprint, forKey: .fingerprint)
    }
}
