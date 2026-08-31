public protocol SemanticOperationLowerer: Sendable {
    var operationID: DomainCapabilityID { get }
    var operationVersion: SemanticOperationVersion { get }
    var resultEstimate: SemanticOperationResultEstimate { get }

    func lower(_ request: SemanticLoweringRequest) throws -> SemanticLoweredOperation
}
