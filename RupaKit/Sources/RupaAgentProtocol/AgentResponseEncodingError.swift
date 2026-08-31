import Foundation

/// Typed failures raised before or during bounded protocol response coding.
public enum AgentResponseEncodingError: Error, Equatable, LocalizedError, Sendable {
    case invalidLimit(name: String, value: Int)
    case requestTooLarge(actual: Int, maximum: Int)
    case responseTooLarge(actual: Int, maximum: Int)
    case invalidIdentifier(name: String)
    case identifierTooLarge(name: String, actual: Int, maximum: Int)
    case unsupportedPlanMethod(String)
    case responsePlanRequired(method: String)
    case invalidPlan(String)
    case chargeExceedsBudget(metric: String, actual: UInt64, maximum: UInt64)
    case chargeOverflow(metric: String)
    case responseDoesNotMatchPlan(expectedID: String, actualID: String?, expectedMethod: String, actualMethod: String?)
    case responseShapeExceedsPlan(actual: Int, reserved: Int)
    case responsePlanAlreadyConsumed

    public var errorDescription: String? {
        switch self {
        case .invalidLimit(let name, let value):
            return "Protocol encoding limit \(name) is invalid; received \(value)."
        case .requestTooLarge(let actual, let maximum):
            return "Encoded request has \(actual) bytes; protocol maximum is \(maximum)."
        case .responseTooLarge(let actual, let maximum):
            return "Encoded response has \(actual) bytes; protocol maximum is \(maximum)."
        case .invalidIdentifier(let name):
            return "Protocol identifier \(name) is empty, padded, or contains control characters."
        case .identifierTooLarge(let name, let actual, let maximum):
            return "Protocol identifier \(name) has \(actual) bytes; maximum is \(maximum)."
        case .unsupportedPlanMethod(let method):
            return "Response encoding plans do not support method \(method)."
        case .responsePlanRequired(let method):
            return "Semantic response \(method) requires a prepublication encoding reservation."
        case .invalidPlan(let message):
            return "The response encoding plan is invalid: \(message)"
        case .chargeExceedsBudget(let metric, let actual, let maximum):
            return "Semantic result charge \(metric) is \(actual), above budget \(maximum)."
        case .chargeOverflow(let metric):
            return "Semantic result charge \(metric) overflowed while planning the response."
        case .responseDoesNotMatchPlan(
            let expectedID,
            let actualID,
            let expectedMethod,
            let actualMethod
        ):
            return "Response does not match plan (id \(expectedID)/\(actualID ?? "nil"), method \(expectedMethod)/\(actualMethod ?? "nil"))."
        case .responseShapeExceedsPlan(let actual, let reserved):
            return "Encoded response shape is \(actual) bytes; plan reserved \(reserved)."
        case .responsePlanAlreadyConsumed:
            return "A response encoding plan may be consumed only once."
        }
    }
}
