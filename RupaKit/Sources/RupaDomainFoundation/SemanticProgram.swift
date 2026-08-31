public struct SemanticProgram: Sendable, Equatable {
    public let schemaVersion: SemanticProgramSchemaVersion
    public let parameters: [ProgramParameterID: SemanticTypedValue]
    public let nodes: [SemanticProgramNode]
    public let requestedOutputs: [SemanticOutputReference]

    public init(
        schemaVersion: SemanticProgramSchemaVersion,
        parameters: [ProgramParameterID: SemanticTypedValue] = [:],
        nodes: [SemanticProgramNode],
        requestedOutputs: [SemanticOutputReference] = []
    ) {
        self.schemaVersion = schemaVersion
        self.parameters = parameters
        self.nodes = nodes
        self.requestedOutputs = requestedOutputs
    }
}
