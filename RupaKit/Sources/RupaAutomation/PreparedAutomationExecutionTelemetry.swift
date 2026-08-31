/// Monotonic measured work from one prepared execution.
public struct PreparedAutomationExecutionTelemetry: Sendable, Equatable {
    public let stepCount: Int
    public let commandCount: Int
    public let inputSlotCount: Int
    public let outputSlotCount: Int
    public let generatedIdentityCount: Int
    public let generatedSourceWork: UInt64

    init(
        stepCount: Int,
        commandCount: Int,
        inputSlotCount: Int,
        outputSlotCount: Int,
        generatedIdentityCount: Int,
        generatedSourceWork: UInt64
    ) {
        self.stepCount = stepCount
        self.commandCount = commandCount
        self.inputSlotCount = inputSlotCount
        self.outputSlotCount = outputSlotCount
        self.generatedIdentityCount = generatedIdentityCount
        self.generatedSourceWork = generatedSourceWork
    }
}
