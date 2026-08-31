public struct SemanticOperationRegistration: Sendable {
    public let descriptor: SemanticOperationDescriptor
    public let lowerer: any SemanticOperationLowerer

    public init(
        descriptor: SemanticOperationDescriptor,
        lowerer: any SemanticOperationLowerer
    ) {
        self.descriptor = descriptor
        self.lowerer = lowerer
    }
}
