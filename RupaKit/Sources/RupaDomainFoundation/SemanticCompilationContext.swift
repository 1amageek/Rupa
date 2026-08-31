public struct SemanticCompilationContext: Sendable, Equatable {
    public let existingSourceReferences: Set<SemanticSourceReference>

    public init(existingSourceReferences: Set<SemanticSourceReference> = []) {
        self.existingSourceReferences = existingSourceReferences
    }

    public func contains(_ reference: SemanticSourceReference) -> Bool {
        existingSourceReferences.contains(reference)
    }
}
