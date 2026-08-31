public struct SemanticOutputReference: Sendable, Equatable, Hashable {
    public let node: ProgramNodeSymbol
    public let output: SemanticOutputID
    public let kind: SemanticReferenceKind

    public init(
        node: ProgramNodeSymbol,
        output: SemanticOutputID,
        kind: SemanticReferenceKind
    ) {
        self.node = node
        self.output = output
        self.kind = kind
    }
}

public typealias ProgramOutputReference = SemanticOutputReference
