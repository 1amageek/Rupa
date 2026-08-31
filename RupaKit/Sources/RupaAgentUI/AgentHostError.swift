import Foundation

public enum AgentHostError: Error, Equatable, LocalizedError, Sendable {
    case startAlreadyInProgress
    case listenerLifetimeEnded
    case missingReadyEndpoint

    public var errorDescription: String? {
        switch self {
        case .startAlreadyInProgress:
            return "The Rupa agent listener is already starting."
        case .listenerLifetimeEnded:
            return "The Rupa agent listener lifetime has ended."
        case .missingReadyEndpoint:
            return "The running Rupa agent listener has no ready endpoint."
        }
    }
}
