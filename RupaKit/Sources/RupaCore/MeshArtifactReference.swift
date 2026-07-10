import SwiftCAD
import RupaCoreTypes

public struct MeshArtifactReference: Codable, Hashable, Sendable {
    public let artifact: MaterializedArtifactReference
    public let configuration: MeshArtifactConfiguration

    public init(
        documentID: DocumentID,
        sourceDependencies: SourceDependencySetIdentity,
        producer: ArtifactProducerReference,
        configuration: MeshArtifactConfiguration,
        contentFingerprint: ContentFingerprint
    ) throws {
        let computation = try ArtifactComputationIdentity(
            documentID: documentID,
            sourceDependencies: sourceDependencies,
            kind: .mesh,
            producer: producer,
            configuration: configuration.identity(),
            determinism: .deterministic
        )
        self.artifact = try MaterializedArtifactReference(
            computation: computation,
            contentFingerprint: contentFingerprint
        )
        self.configuration = configuration
    }

    public var documentID: DocumentID {
        artifact.documentID
    }

    public var producer: ArtifactProducerReference {
        artifact.computation.producer
    }

    public var sourceDependencies: SourceDependencySetIdentity {
        artifact.computation.sourceDependencies
    }

    public var kernelVersion: SchemaVersion {
        configuration.kernelVersion
    }

    public var modelingTolerance: ModelingTolerance {
        configuration.modelingTolerance
    }

    public var tessellationOptions: TessellationOptions {
        configuration.tessellationOptions
    }

    public func validate() throws {
        guard artifact.kind == .mesh else {
            throw ReferenceValidationError(
                code: .invalidIdentity,
                message: "Mesh artifact references must use the mesh artifact kind."
            )
        }
        guard artifact.computation.configuration == (try configuration.identity()) else {
            throw ReferenceValidationError(
                code: .invalidIdentity,
                message: "Mesh artifact configuration does not match its computation identity."
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case artifact
        case configuration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.artifact = try container.decode(MaterializedArtifactReference.self, forKey: .artifact)
        self.configuration = try container.decode(MeshArtifactConfiguration.self, forKey: .configuration)
        try validate()
    }
}
