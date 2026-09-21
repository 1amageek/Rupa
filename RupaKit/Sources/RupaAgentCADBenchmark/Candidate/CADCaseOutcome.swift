public enum CADCaseOutcome: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case realized
    case expectedUnsupported
    case unexpectedUnsupported
    case invalidSubmission
    case executionFailure
    case oracleFailure
    case timeout
    case cancellation
    case infrastructureFailure
}
