public enum SemanticCompilationError: Error, Equatable, Sendable {
    case unsupportedSchema(SemanticProgramSchemaVersion)
    case unknownOperation(DomainCapabilityID, SemanticOperationVersion)
    case unsupportedOperationVersion(DomainCapabilityID, SemanticOperationVersion)
    case emptyProgram
    case invalidIdentifier(String)
    case directLocalReference(SemanticArgumentID)
    case directOutputMissing(SemanticOutputID)
    case duplicateDirectOutput(SemanticOutputID)
    case duplicateNode(ProgramNodeSymbol)
    case duplicateOutput(SemanticOutputID)
    case missingArgument(node: ProgramNodeSymbol, argument: SemanticArgumentID)
    case unknownArgument(node: ProgramNodeSymbol, argument: SemanticArgumentID)
    case invalidArgument(node: ProgramNodeSymbol, argument: SemanticArgumentID)
    case missingParameter(ProgramParameterID)
    case invalidParameter(ProgramParameterID)
    case parameterTypeMismatch(ProgramParameterID, expected: SemanticValueType, actual: SemanticValueType)
    case sourceReferenceUnavailable(SemanticSourceReference)
    case sourceReferenceTypeMismatch(
        node: ProgramNodeSymbol,
        argument: SemanticArgumentID,
        expected: SemanticValueType,
        actual: SemanticValueType
    )
    case localReferenceNodeMissing(node: ProgramNodeSymbol, reference: ProgramNodeSymbol)
    case localReferenceOutputMissing(node: ProgramNodeSymbol, output: SemanticOutputID)
    case localReferenceSelf(node: ProgramNodeSymbol)
    case localReferenceKindMismatch(
        node: ProgramNodeSymbol,
        argument: SemanticArgumentID,
        expected: SemanticValueType,
        actual: SemanticValueType
    )
    case requestedOutputNodeMissing(ProgramNodeSymbol)
    case requestedOutputMissing(node: ProgramNodeSymbol, output: SemanticOutputID)
    case requestedOutputKindMismatch(
        node: ProgramNodeSymbol,
        output: SemanticOutputID,
        expected: SemanticValueType,
        actual: SemanticValueType
    )
    case duplicateRequestedOutput(SemanticOutputReference)
    case graphCycle([ProgramNodeSymbol])
    case routeIneligible(node: ProgramNodeSymbol, route: SemanticOperationRoute)
    case effectIneligible(node: ProgramNodeSymbol, effect: SemanticOperationEffect)
    case aggregateEffectIneligible
    case invalidOperationCost(node: ProgramNodeSymbol)
    case limitExceeded(metric: SemanticProgramLimitMetric, actual: UInt64, maximum: UInt64)
    case arithmeticInvalid
    case cancelled
    case loweringFailed(
        node: ProgramNodeSymbol,
        operationID: DomainCapabilityID,
        code: DomainCapabilityErrorCode,
        message: String
    )
    case lowererContractViolation(node: ProgramNodeSymbol, message: String)
    case preparedPlanInvalid(node: ProgramNodeSymbol?, message: String)
}
