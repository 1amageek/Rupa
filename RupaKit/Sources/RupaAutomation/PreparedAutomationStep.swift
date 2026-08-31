/// One ordered source-command step in a prepared program.
public struct PreparedAutomationStep: Sendable {
    public let inputs: [PreparedAutomationInputSlot]
    public let outputs: [PreparedAutomationOutputSlot]
    public let estimatedGeneratedSourceWork: UInt64
    public let commandBuilder: PreparedAutomationCommandBuilder

    public init(
        inputs: [PreparedAutomationInputSlot] = [],
        outputs: [PreparedAutomationOutputSlot] = [],
        estimatedGeneratedSourceWork: UInt64,
        commandBuilder: PreparedAutomationCommandBuilder
    ) {
        self.inputs = inputs
        self.outputs = outputs
        self.estimatedGeneratedSourceWork = estimatedGeneratedSourceWork
        self.commandBuilder = commandBuilder
    }
}
