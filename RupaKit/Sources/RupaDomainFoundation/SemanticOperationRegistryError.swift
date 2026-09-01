public enum SemanticOperationRegistryError: Error, Equatable, Sendable {
    case invalidOperationID
    case invalidInputID(SemanticArgumentID)
    case invalidOutputID(SemanticOutputID)
    case duplicateInput(SemanticArgumentID)
    case duplicateOutput(SemanticOutputID)
    case duplicateOutputSelector(SemanticOutputSelector)
    case outputSelectorKindMismatch(SemanticOutputID)
    case negativeOutputIndex(SemanticOutputID)
    case invalidSourceWork
    case lowererIdentityMismatch
    case lowererResultEstimateMismatch
    case duplicateOperation(DomainCapabilityID, SemanticOperationVersion)
    case missingOperation(DomainCapabilityID, SemanticOperationVersion)
    case unexpectedOperation(DomainCapabilityID, SemanticOperationVersion)
}
