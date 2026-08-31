import RupaCore

/// Builds one already-resolved Core command from typed prepared inputs.
public struct PreparedAutomationCommandBuilder: Sendable {
    public let name: String
    private let operation: @Sendable (PreparedAutomationResolvedInputs) throws -> ContextResolvedEditorCommand

    package init(
        name: String,
        operation: @escaping @Sendable (PreparedAutomationResolvedInputs) throws -> ContextResolvedEditorCommand
    ) {
        self.name = name
        self.operation = operation
    }

    func build(
        from inputs: PreparedAutomationResolvedInputs
    ) throws -> ContextResolvedEditorCommand {
        try operation(inputs)
    }
}
