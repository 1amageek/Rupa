import RupaAgentCADBenchmark
import RupaAgentCADBenchmarkJSONAdapter

enum CADBenchmarkCLIExitCode: Int32, Equatable, Sendable {
    case success = 0
    case nonRealized = 2
    case usage = 64
    case software = 70

    static func value(for error: Error) -> Self {
        guard let error = error as? CADJSONAdapterError else {
            return .software
        }
        return value(for: error.code)
    }

    static func value(for code: CADJSONErrorCode) -> Self {
        switch code {
        case .timeout, .cancellation:
            .nonRealized
        case .candidateFailure, .oracleFailure, .infrastructureFailure, .outputOverflow:
            .software
        case .malformedUTF8,
             .malformedJSON,
             .oversizedInput,
             .unsupportedSchema,
             .inactiveCase,
             .caseMismatch,
             .fingerprintMismatch,
             .invalidDecision,
             .directoryInput,
             .trailingData,
             .unsupportedInputSource,
             .inputFailure:
            .usage
        }
    }

    static func value(for result: CADCaseResult) -> Self {
        switch result.outcome {
        case .realized:
            .success
        case .expectedUnsupported,
             .unexpectedUnsupported,
             .invalidSubmission,
             .timeout,
             .cancellation:
            .nonRealized
        case .executionFailure,
             .oracleFailure,
             .infrastructureFailure:
            .software
        }
    }
}
