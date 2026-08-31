import RupaCore

/// Immutable evidence for one executed prepared source step.
public struct PreparedAutomationStepReceipt: Sendable, Equatable {
    public let stepIndex: Int
    public let commandName: String
    public let generatedIdentities: CommandGeneratedIdentityDelta
    public let outputBindings: [PreparedAutomationOutputBinding]

    init(
        stepIndex: Int,
        commandName: String,
        generatedIdentities: CommandGeneratedIdentityDelta,
        outputBindings: [PreparedAutomationOutputBinding]
    ) {
        self.stepIndex = stepIndex
        self.commandName = commandName
        self.generatedIdentities = generatedIdentities
        self.outputBindings = outputBindings
    }
}
