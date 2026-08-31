/// A typed domain failure raised while lowering one validated semantic operation.
public protocol SemanticOperationLoweringFailure: Error, Sendable {
  var semanticErrorCode: DomainCapabilityErrorCode { get }
  var semanticErrorMessage: String { get }
}
