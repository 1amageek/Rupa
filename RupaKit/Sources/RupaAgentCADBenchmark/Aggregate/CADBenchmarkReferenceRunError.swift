enum CADBenchmarkReferenceRunError: Error, Equatable, Sendable {
    case activationMismatch
    case contextMismatch(CADBenchmarkCaseID)
    case missingCase(CADBenchmarkCaseID)
    case duplicateCase(CADBenchmarkCaseID)
    case invalidEvidence(CADBenchmarkCaseID)
    case invalidOutcome(CADBenchmarkCaseID)
    case incompleteRun(expected: Int, actual: Int)
}
