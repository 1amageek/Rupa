public struct SemanticOperationDescriptor: Sendable, Equatable, Hashable {
    public let operationID: DomainCapabilityID
    public let version: SemanticOperationVersion
    public let inputs: [SemanticOperationInputDescriptor]
    public let outputs: [SemanticOperationOutputDescriptor]
    public let route: SemanticOperationRoute
    public let effect: SemanticOperationEffect
    /// The minimum generated-source work for any accepted invocation.
    ///
    /// Lowerers with argument-dependent work report the exact value during the
    /// compiler's complete pre-lowering estimation pass.
    public let estimatedExpandedSourceWork: UInt64
    public let resultEstimate: SemanticOperationResultEstimate

    public init(
        operationID: DomainCapabilityID,
        version: SemanticOperationVersion,
        inputs: [SemanticOperationInputDescriptor] = [],
        outputs: [SemanticOperationOutputDescriptor],
        route: SemanticOperationRoute,
        effect: SemanticOperationEffect,
        estimatedExpandedSourceWork: UInt64,
        resultEstimate: SemanticOperationResultEstimate
    ) {
        self.operationID = operationID
        self.version = version
        self.inputs = inputs
        self.outputs = outputs
        self.route = route
        self.effect = effect
        self.estimatedExpandedSourceWork = estimatedExpandedSourceWork
        self.resultEstimate = resultEstimate
    }
}
