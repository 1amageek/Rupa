import RupaDomainFoundation

public struct RupaCADDomainError: Error, Equatable, Sendable,
  SemanticOperationLoweringFailure
{
  public static let invalidArgumentCode: DomainCapabilityErrorCode = "cad.invalidArgument"
  public static let degenerateGeometryCode: DomainCapabilityErrorCode = "cad.degenerateGeometry"
  public static let invalidReferenceCode: DomainCapabilityErrorCode = "cad.invalidReference"
  public static let referenceKindMismatchCode: DomainCapabilityErrorCode =
    "cad.referenceKindMismatch"
  public static let unsupportedValueCode: DomainCapabilityErrorCode = "cad.unsupportedValue"
  public static let coreCommandRejectedCode: DomainCapabilityErrorCode = "cad.coreCommandRejected"

  public let code: DomainCapabilityErrorCode
  public let message: String

  public init(code: DomainCapabilityErrorCode, message: String) {
    self.code = code
    self.message = message
  }

  public var semanticErrorCode: DomainCapabilityErrorCode { code }
  public var semanticErrorMessage: String { message }
}
