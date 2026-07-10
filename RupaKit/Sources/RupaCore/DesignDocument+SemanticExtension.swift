extension DesignDocument {
    mutating func applySemanticExtensionMutations(
        _ mutations: [SemanticExtensionMutation],
        objectRegistry: ObjectTypeRegistry
    ) throws {
        guard !mutations.isEmpty else {
            throw EditorError(
                code: .commandInvalid,
                message: "Semantic extension mutation batches must not be empty."
            )
        }

        var metadata = productMetadata
        for mutation in mutations {
            switch mutation {
            case .upsert(let envelope):
                metadata.semanticExtensions[envelope.id] = envelope
            case .remove(let extensionID):
                guard let existing = metadata.semanticExtensions[extensionID] else {
                    throw EditorError(
                        code: .referenceUnresolved,
                        message: "Semantic extension \(extensionID.rawValue.uuidString) does not exist."
                    )
                }
                let retainedDomainSources = existing.projection.sourceReferences.filter { reference in
                    reference.ownership == .domainOwned
                        && cadDocument.designGraph.nodes[reference.featureID] != nil
                }
                guard retainedDomainSources.isEmpty else {
                    throw EditorError(
                        code: .commandInvalid,
                        message: "Domain-owned CAD source must be removed or transferred to universal ownership before removing its semantic extension."
                    )
                }
                metadata.semanticExtensions.removeValue(forKey: extensionID)
            }
        }
        try metadata.validate(
            against: cadDocument,
            objectRegistry: objectRegistry
        )
        productMetadata = metadata
    }
}
