public enum CADJSONErrorCode: String, Codable, Equatable, Hashable, Sendable {
    case malformedUTF8 = "malformed_utf8"
    case malformedJSON = "malformed_json"
    case oversizedInput = "oversized_input"
    case unsupportedSchema = "unsupported_schema"
    case inactiveCase = "inactive_case"
    case caseMismatch = "case_mismatch"
    case fingerprintMismatch = "fingerprint_mismatch"
    case invalidDecision = "invalid_decision"
    case candidateFailure = "candidate_failure"
    case timeout = "timeout"
    case cancellation = "cancellation"
    case oracleFailure = "oracle_failure"
    case infrastructureFailure = "infrastructure_failure"
    case outputOverflow = "output_overflow"
    case directoryInput = "directory_input"
    case trailingData = "trailing_data"
    case unsupportedInputSource = "unsupported_input_source"
    case inputFailure = "input_failure"

    public var stableMessage: String {
        switch self {
        case .malformedUTF8:
            "Input is not valid UTF-8."
        case .malformedJSON:
            "Input is not valid JSON for the requested envelope."
        case .oversizedInput:
            "The JSON document exceeds the maximum byte limit."
        case .unsupportedSchema:
            "The JSON schema version is not supported."
        case .inactiveCase:
            "The benchmark case is not activated."
        case .caseMismatch:
            "The response case does not match the requested case."
        case .fingerprintMismatch:
            "The public context fingerprint does not match the live context."
        case .invalidDecision:
            "The candidate decision is invalid."
        case .candidateFailure:
            "The candidate failed before a sanitized result was produced."
        case .timeout:
            "The benchmark case timed out."
        case .cancellation:
            "The benchmark case was cancelled."
        case .oracleFailure:
            "The benchmark oracle failed."
        case .infrastructureFailure:
            "The benchmark infrastructure failed."
        case .outputOverflow:
            "The encoded JSON document exceeds the maximum byte limit."
        case .directoryInput:
            "The selected input path is a directory."
        case .trailingData:
            "The JSON document contains trailing non-whitespace data."
        case .unsupportedInputSource:
            "Only standard input and regular local files are supported."
        case .inputFailure:
            "The input could not be read."
        }
    }
}
