import Foundation
import RupaAgentTransport
import RupaProjectAccess

@MainActor
func mapLiveProjectTransportError(_ error: Error) -> Error {
    guard let failure = error as? AgentTransportFailure else {
        return error
    }

    switch failure.disposition {
    case .outcomeUnknown(let requestID):
        return ProjectAccessError.outcomeUnknown(requestID: requestID)
    case .notDispatched:
        switch failure.cause {
        case .cancelled:
            return CancellationError()
        case .deadlineExceeded:
            return ProjectAccessError.deadlineExceeded
        case .transport(let editorError):
            return editorError
        }
    }
}

@MainActor
func checkLiveProjectDeadline(_ deadline: ContinuousClock.Instant) throws {
    try Task.checkCancellation()
    guard ContinuousClock.now < deadline else {
        throw ProjectAccessError.deadlineExceeded
    }
}
