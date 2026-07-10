import SwiftCAD

public struct ValidationInputIdentity: Codable, Hashable, Sendable {
    public let documentID: DocumentID
    public let sourceDependencies: SourceDependencySetIdentity
    public let configuration: ArtifactConfigurationIdentity
    public let artifacts: [MaterializedArtifactReference]

    public init(
        documentID: DocumentID,
        sourceDependencies: SourceDependencySetIdentity,
        configuration: ArtifactConfigurationIdentity,
        artifacts: [MaterializedArtifactReference] = []
    ) throws {
        self.documentID = documentID
        self.sourceDependencies = sourceDependencies
        self.configuration = configuration
        self.artifacts = artifacts.sorted {
            let first = $0.fingerprint.algorithm + ":" + $0.fingerprint.value
            let second = $1.fingerprint.algorithm + ":" + $1.fingerprint.value
            return first < second
        }
        try validate()
    }

    public func validate() throws {
        let hasDocumentDependency = sourceDependencies.dependencies.contains { dependency in
            switch dependency.subject {
            case .cadDocument(let id), .rupaDocument(let id):
                id == documentID
            case .linkedDocument, .semanticEntity, .external:
                false
            }
        }
        guard hasDocumentDependency else {
            throw ReferenceValidationError(
                code: .documentMismatch,
                message: "Validation inputs require a source dependency for their document."
            )
        }
        guard Set(artifacts.map(\.fingerprint)).count == artifacts.count else {
            throw ReferenceValidationError(
                code: .invalidIdentity,
                message: "Validation input artifact identities must be unique."
            )
        }

        let dependencies = Set(sourceDependencies.dependencies)
        for artifact in artifacts {
            guard artifact.documentID == documentID else {
                throw ReferenceValidationError(
                    code: .documentMismatch,
                    message: "Validation artifacts and source inputs must reference one document."
                )
            }
            let artifactDependencies = Set(artifact.computation.sourceDependencies.dependencies)
            guard artifactDependencies.isSubset(of: dependencies) else {
                throw ReferenceValidationError(
                    code: .invalidIdentity,
                    message: "Validation inputs must include every source dependency consumed by their artifacts."
                )
            }
        }
    }

    public func matchesCurrentInput(_ other: ValidationInputIdentity) -> Bool {
        self == other
    }

    private enum CodingKeys: String, CodingKey {
        case documentID
        case sourceDependencies
        case configuration
        case artifacts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            documentID: container.decode(DocumentID.self, forKey: .documentID),
            sourceDependencies: container.decode(SourceDependencySetIdentity.self, forKey: .sourceDependencies),
            configuration: container.decode(ArtifactConfigurationIdentity.self, forKey: .configuration),
            artifacts: container.decode([MaterializedArtifactReference].self, forKey: .artifacts)
        )
    }
}
