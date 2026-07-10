public struct ProjectionSemanticEntity: Codable, Hashable, Sendable, Identifiable {
    public var id: SemanticEntityID
    public var ownership: SemanticOwnershipPolicy
    public var sourcePaths: [SemanticPayloadPath]
    public var dependencyIdentity: ProjectionDependencyIdentity?

    public init(
        id: SemanticEntityID,
        ownership: SemanticOwnershipPolicy,
        sourcePaths: [SemanticPayloadPath],
        dependencyIdentity: ProjectionDependencyIdentity? = nil
    ) {
        self.id = id
        self.ownership = ownership
        self.sourcePaths = sourcePaths
        self.dependencyIdentity = dependencyIdentity
    }

    public func validate() throws {
        try id.validate()
        guard !sourcePaths.isEmpty,
              Set(sourcePaths).count == sourcePaths.count else {
            throw DocumentValidationError.invalidProductMetadata(
                "Projection semantic entities must declare unique semantic source paths."
            )
        }
        for sourcePath in sourcePaths {
            try sourcePath.validate()
        }
        try dependencyIdentity?.validate()
    }
}
