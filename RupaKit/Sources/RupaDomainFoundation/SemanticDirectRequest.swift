public struct SemanticDirectRequest: Sendable, Equatable {
    public let schemaVersion: SemanticProgramSchemaVersion
    public let invocation: SemanticOperationInvocation
    public let requestedOutputs: [SemanticOutputID]

    public init(
        schemaVersion: SemanticProgramSchemaVersion,
        invocation: SemanticOperationInvocation,
        requestedOutputs: [SemanticOutputID] = []
    ) {
        self.schemaVersion = schemaVersion
        self.invocation = invocation
        self.requestedOutputs = requestedOutputs
    }
}
