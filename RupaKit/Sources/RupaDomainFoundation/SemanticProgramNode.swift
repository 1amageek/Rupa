public struct SemanticProgramNode: Sendable, Equatable {
    public let symbol: ProgramNodeSymbol
    public let invocation: SemanticOperationInvocation

    public init(
        symbol: ProgramNodeSymbol,
        invocation: SemanticOperationInvocation
    ) {
        self.symbol = symbol
        self.invocation = invocation
    }
}
