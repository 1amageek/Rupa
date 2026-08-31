import Foundation

public enum AgentHTTPError: Error, Equatable, LocalizedError, Sendable {
    case invalidEndpoint
    case invalidKey
    case invalidGeneration
    case randomnessUnavailable
    case deadlineExceeded
    case cancelled
    case connectionFailed(String)
    case listenerFailed(String)
    case malformedMessage(String)
    case unsupportedRoute
    case authenticationFailed
    case challengeExpired
    case bodyTooLarge(Int)
    case missingContentLength
    case unexpectedStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "The agent endpoint must be a non-zero loopback port."
        case .invalidKey:
            return "The agent authentication key is invalid."
        case .invalidGeneration:
            return "The agent launch generation is invalid."
        case .randomnessUnavailable:
            return "The operating system could not provide agent authentication randomness."
        case .deadlineExceeded:
            return "The agent transport deadline was exceeded."
        case .cancelled:
            return "The agent transport operation was cancelled."
        case .connectionFailed(let message):
            return message
        case .listenerFailed(let message):
            return message
        case .malformedMessage(let message):
            return message
        case .unsupportedRoute:
            return "The agent HTTP route is not supported."
        case .authenticationFailed:
            return "The agent authentication proof is invalid."
        case .challengeExpired:
            return "The agent authentication challenge expired."
        case .bodyTooLarge(let count):
            return "The agent HTTP body has \(count) bytes, exceeding the configured limit."
        case .missingContentLength:
            return "The agent HTTP request must provide Content-Length."
        case .unexpectedStatus(let status):
            return "The agent HTTP response returned status \(status)."
        }
    }
}
