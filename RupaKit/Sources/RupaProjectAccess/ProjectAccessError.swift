import Foundation
import RupaAgentProtocol

public enum ProjectAccessError: Error, Equatable, Sendable {
    case invalidTarget(URL)
    case unsupportedProjectFormat(URL)
    case sessionMismatch(expected: UUID, actual: UUID)
    case sessionUnavailable(UUID?)
    case deadlineExceeded
    case saveUnavailable
    case outcomeUnknown(requestID: UUID?)
    case finished
    case authorityUnavailable
    case committedMutation(AgentCommittedMutationOutcome)
}

extension ProjectAccessError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidTarget(let url):
            "The project access target is invalid: \(url.path)."
        case .unsupportedProjectFormat(let url):
            "Project access supports schema-v3 .rupa packages only: \(url.path)."
        case .sessionMismatch(let expected, let actual):
            "The request session \(actual.uuidString) does not match the opened session \(expected.uuidString)."
        case .sessionUnavailable(let sessionID):
            if let sessionID {
                "The live project session is unavailable: \(sessionID.uuidString)."
            } else {
                "The live project session is unavailable."
            }
        case .deadlineExceeded:
            "The project access deadline was exceeded."
        case .saveUnavailable:
            "Explicit save is unavailable for this project access session."
        case .outcomeUnknown(let requestID):
            if let requestID {
                "The project mutation outcome is unknown for request \(requestID.uuidString)."
            } else {
                "The project mutation outcome is unknown."
            }
        case .finished:
            "The project access session has already finished."
        case .authorityUnavailable:
            "The required ProjectWorkspace and ProjectController authority is unavailable."
        case .committedMutation(let outcome):
            outcome.message
        }
    }
}
