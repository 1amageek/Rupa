import RupaCoreTypes

/// Canonicalizes one semantic mutation against the exact document state that will own it.
public struct NamespacedSemanticExtensionMutationCanonicalizer: Sendable {
    public init() {}

    public func canonicalize(
        _ mutation: SemanticExtensionMutation,
        namespace: SemanticNamespaceID,
        generation: DocumentGeneration,
        in document: DesignDocument
    ) throws -> SemanticExtensionMutation {
        switch mutation {
        case .upsert(var envelope):
            guard envelope.namespace == namespace else {
                throw crossNamespaceMutationError()
            }
            for index in envelope.projection.semanticEntities.indices {
                let semanticEntityID = envelope.projection.semanticEntities[index].id
                envelope.projection.semanticEntities[index].dependencyIdentity = envelope.projection
                    .hasSourceBoundReferences(for: semanticEntityID)
                    ? try ProjectionDependencyIdentityBuilder().identity(
                        for: semanticEntityID,
                        in: envelope,
                        document: document,
                        generation: generation
                    )
                    : nil
            }
            return .upsert(envelope)
        case .remove(let extensionID):
            guard let envelope = document.productMetadata.semanticExtensions[extensionID] else {
                throw EditorError(
                    code: .referenceUnresolved,
                    message: "Semantic extension \(extensionID.rawValue.uuidString) does not exist."
                )
            }
            guard envelope.namespace == namespace else {
                throw crossNamespaceMutationError()
            }
            return mutation
        }
    }

    public func canonicalize(
        _ mutations: [SemanticExtensionMutation],
        namespace: SemanticNamespaceID,
        generation: DocumentGeneration,
        in document: DesignDocument
    ) throws -> [SemanticExtensionMutation] {
        try mutations.map { mutation in
            try canonicalize(
                mutation,
                namespace: namespace,
                generation: generation,
                in: document
            )
        }
    }

    private func crossNamespaceMutationError() -> EditorError {
        EditorError(
            code: .commandInvalid,
            message: "Domain transactions cannot mutate another semantic namespace."
        )
    }
}
