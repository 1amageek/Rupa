import Foundation
import RupaCoreTypes

public struct AgentTransportFailure: Error, Equatable, Sendable {
    public enum DispatchDisposition: Equatable, Sendable {
        case notDispatched
        case outcomeUnknown(requestID: UUID)
    }

    public enum Cause: Equatable, Sendable {
        case cancelled
        case deadlineExceeded
        case transport(EditorError)
    }

    public let disposition: DispatchDisposition
    public let cause: Cause

    public init(
        disposition: DispatchDisposition,
        cause: Cause
    ) {
        self.disposition = disposition
        self.cause = cause
    }
}
