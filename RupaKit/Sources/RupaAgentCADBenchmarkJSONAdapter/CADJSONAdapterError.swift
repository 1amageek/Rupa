public enum CADJSONAdapterError: Error, Equatable, Sendable, CustomStringConvertible {
    case malformedUTF8
    case malformedJSON
    case oversizedInput
    case unsupportedSchema
    case inactiveCase
    case caseMismatch
    case fingerprintMismatch
    case invalidDecision
    case candidateFailure
    case timeout
    case cancellation
    case oracleFailure
    case infrastructureFailure
    case outputOverflow
    case directoryInput
    case trailingData
    case unsupportedInputSource
    case inputFailure

    public var code: CADJSONErrorCode {
        switch self {
        case .malformedUTF8: .malformedUTF8
        case .malformedJSON: .malformedJSON
        case .oversizedInput: .oversizedInput
        case .unsupportedSchema: .unsupportedSchema
        case .inactiveCase: .inactiveCase
        case .caseMismatch: .caseMismatch
        case .fingerprintMismatch: .fingerprintMismatch
        case .invalidDecision: .invalidDecision
        case .candidateFailure: .candidateFailure
        case .timeout: .timeout
        case .cancellation: .cancellation
        case .oracleFailure: .oracleFailure
        case .infrastructureFailure: .infrastructureFailure
        case .outputOverflow: .outputOverflow
        case .directoryInput: .directoryInput
        case .trailingData: .trailingData
        case .unsupportedInputSource: .unsupportedInputSource
        case .inputFailure: .inputFailure
        }
    }

    public var description: String {
        code.stableMessage
    }
}
