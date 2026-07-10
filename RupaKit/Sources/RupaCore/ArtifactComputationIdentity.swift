import SwiftCAD
import RupaCoreTypes

public struct ArtifactComputationIdentity: Codable, Hashable, Sendable {
    public let documentID: DocumentID
    public let sourceDependencies: SourceDependencySetIdentity
    public let kind: DerivedArtifactKind
    public let producer: ArtifactProducerReference
    public let configuration: ArtifactConfigurationIdentity
    public let determinism: ArtifactDeterminism
    public let fingerprint: ContentFingerprint

    public init(
        documentID: DocumentID,
        sourceDependencies: SourceDependencySetIdentity,
        kind: DerivedArtifactKind,
        producer: ArtifactProducerReference,
        configuration: ArtifactConfigurationIdentity,
        determinism: ArtifactDeterminism
    ) throws {
        try kind.validate()
        try producer.validate()
        self.documentID = documentID
        self.sourceDependencies = sourceDependencies
        self.kind = kind
        self.producer = producer
        self.configuration = configuration
        self.determinism = determinism
        var hasher = CanonicalIdentityHasher(domain: "artifact-computation.v1")
        hasher.appendField("documentID")
        hasher.appendString(documentID.description)
        hasher.appendField("sourceDependencies")
        hasher.appendString(sourceDependencies.fingerprint.algorithm)
        hasher.appendString(sourceDependencies.fingerprint.value)
        hasher.appendField("kind")
        hasher.appendString(kind.rawValue)
        hasher.appendField("producer")
        hasher.appendString(producer.id)
        hasher.appendString(producer.version)
        hasher.appendField("configuration")
        hasher.appendString(configuration.fingerprint.algorithm)
        hasher.appendString(configuration.fingerprint.value)
        hasher.appendField("determinism")
        hasher.appendString(determinism.rawValue)
        self.fingerprint = try hasher.fingerprint(
            algorithm: "sha256-artifact-computation-v1"
        )
    }

    private enum CodingKeys: String, CodingKey {
        case documentID
        case sourceDependencies
        case kind
        case producer
        case configuration
        case determinism
        case fingerprint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let encodedFingerprint = try container.decode(ContentFingerprint.self, forKey: .fingerprint)
        try self.init(
            documentID: container.decode(DocumentID.self, forKey: .documentID),
            sourceDependencies: container.decode(SourceDependencySetIdentity.self, forKey: .sourceDependencies),
            kind: container.decode(DerivedArtifactKind.self, forKey: .kind),
            producer: container.decode(ArtifactProducerReference.self, forKey: .producer),
            configuration: container.decode(ArtifactConfigurationIdentity.self, forKey: .configuration),
            determinism: container.decode(ArtifactDeterminism.self, forKey: .determinism)
        )
        guard fingerprint == encodedFingerprint else {
            throw ReferenceValidationError(
                code: .invalidIdentity,
                message: "Artifact computation fingerprint does not match its inputs."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(documentID, forKey: .documentID)
        try container.encode(sourceDependencies, forKey: .sourceDependencies)
        try container.encode(kind, forKey: .kind)
        try container.encode(producer, forKey: .producer)
        try container.encode(configuration, forKey: .configuration)
        try container.encode(determinism, forKey: .determinism)
        try container.encode(fingerprint, forKey: .fingerprint)
    }
}
