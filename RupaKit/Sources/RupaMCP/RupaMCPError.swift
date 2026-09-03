import Foundation

public enum RupaMCPError: Error, Equatable, LocalizedError, Sendable {
    case invalidArguments(String)
    case requestTooLarge(actual: Int, maximum: Int)
    case responseTooLarge(actual: Int, maximum: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidArguments(let message):
            message
        case .requestTooLarge(let actual, let maximum):
            "MCP tool arguments contain \(actual) bytes; the maximum is \(maximum)."
        case .responseTooLarge(let actual, let maximum):
            "Rupa returned \(actual) bytes; the maximum MCP result is \(maximum)."
        }
    }

    var code: String {
        switch self {
        case .invalidArguments:
            "invalidArguments"
        case .requestTooLarge:
            "requestTooLarge"
        case .responseTooLarge:
            "responseTooLarge"
        }
    }
}
