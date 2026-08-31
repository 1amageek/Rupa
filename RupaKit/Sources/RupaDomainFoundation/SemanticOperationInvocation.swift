import RupaCoreTypes

public struct SemanticOperationInvocation: Sendable, Equatable {
    public let operationID: DomainCapabilityID
    public let operationVersion: SemanticOperationVersion
    public let arguments: [SemanticArgumentID: SemanticArgument]

    public init(
        operationID: DomainCapabilityID,
        operationVersion: SemanticOperationVersion,
        arguments: [SemanticArgumentID: SemanticArgument] = [:]
    ) {
        self.operationID = operationID
        self.operationVersion = operationVersion
        self.arguments = arguments
    }
}
