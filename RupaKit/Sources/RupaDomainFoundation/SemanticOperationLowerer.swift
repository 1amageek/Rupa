public protocol SemanticOperationLowerer: Sendable {
    var operationID: DomainCapabilityID { get }
    var operationVersion: SemanticOperationVersion { get }
    var resultEstimate: SemanticOperationResultEstimate { get }

    func estimateGeneratedSourceWork(
        for request: SemanticLoweringRequest
    ) throws -> UInt64

    func lower(_ request: SemanticLoweringRequest) throws -> SemanticLoweredOperation
}

public extension SemanticOperationLowerer {
    func estimateGeneratedSourceWork(
        for request: SemanticLoweringRequest
    ) throws -> UInt64 {
        request.descriptor.estimatedExpandedSourceWork
    }
}
