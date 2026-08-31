import RupaAutomation

public struct SemanticLoweringRequest: Sendable {
    public let descriptor: SemanticOperationDescriptor
    public let invocation: SemanticOperationInvocation
    public let arguments: [SemanticArgumentID: SemanticResolvedArgument]
    public let preparedInputs: [PreparedAutomationInputSlot]
    public let preparedOutputs: [PreparedAutomationOutputSlot]

    init(
        descriptor: SemanticOperationDescriptor,
        invocation: SemanticOperationInvocation,
        arguments: [SemanticArgumentID: SemanticResolvedArgument],
        preparedInputs: [PreparedAutomationInputSlot],
        preparedOutputs: [PreparedAutomationOutputSlot]
    ) {
        self.descriptor = descriptor
        self.invocation = invocation
        self.arguments = arguments
        self.preparedInputs = preparedInputs
        self.preparedOutputs = preparedOutputs
    }
}
