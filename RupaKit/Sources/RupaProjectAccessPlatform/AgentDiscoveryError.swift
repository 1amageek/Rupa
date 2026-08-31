import Foundation

public enum AgentDiscoveryError: Error, Equatable, LocalizedError, Sendable {
    case invalidPort
    case invalidGeneration
    case invalidKeyLength(Int)
    case invalidConfiguration
    case unavailable(String)
    case unauthorized(String)
    case malformed(String)
    case staleGeneration(expected: UInt64, actual: UInt64?)

    public var errorDescription: String? {
        switch self {
        case .invalidPort:
            return "The published agent port is invalid."
        case .invalidGeneration:
            return "The published agent generation is invalid."
        case .invalidKeyLength(let count):
            return "The published agent key has \(count) bytes instead of 32."
        case .invalidConfiguration:
            return "The Keychain discovery configuration is incomplete."
        case .unavailable(let message):
            return "Agent discovery is unavailable: \(message)"
        case .unauthorized(let message):
            return "Agent discovery is unauthorized: \(message)"
        case .malformed(let message):
            return "Agent discovery data is malformed: \(message)"
        case .staleGeneration(let expected, let actual):
            return "Agent discovery generation \(actual.map(String.init) ?? "none") does not match \(expected)."
        }
    }
}
