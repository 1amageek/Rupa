import Foundation
import RupaAgentProtocol
import RupaCoreTypes
import RupaProjectAccess

/// An access handle attached to one App-owned Agent session.
@MainActor
public final class LiveProjectAccessSession: ProjectAccessSession {
    public nonisolated let sessionID: UUID

    private var transport: (any LiveProjectAccessTransport)?
    private let deadline: ContinuousClock.Instant
    private let sequencer = LiveProjectAccessOperationSequencer()

    init(
        sessionID: UUID,
        transport: any LiveProjectAccessTransport,
        deadline: ContinuousClock.Instant
    ) {
        self.sessionID = sessionID
        self.transport = transport
        self.deadline = deadline
    }

    public func send(_ request: AgentRequest) async throws -> AgentResponse {
        try await sequencer.enqueue { [self] in
            guard transport != nil else {
                throw ProjectAccessError.finished
            }
            try checkLiveProjectDeadline(deadline)
            try validateSessionIdentity(of: request)
            guard case .save = request else {
                return try await dispatch(request)
            }
            throw ProjectAccessError.saveUnavailable
        }
    }

    private func dispatch(_ request: AgentRequest) async throws -> AgentResponse {
        guard let transport else {
            throw ProjectAccessError.finished
        }
        do {
            return try await transport.send(request, deadline: deadline)
        } catch {
            throw mapLiveProjectTransportError(error)
        }
    }

    public func save(
        expectedGeneration: DocumentGeneration?
    ) async throws -> SaveResult {
        try await sequencer.enqueue { [self] in
            guard transport != nil else {
                throw ProjectAccessError.finished
            }
            try checkLiveProjectDeadline(deadline)
            let response = try await dispatch(
                .save(
                    sessionID: sessionID,
                    expectedGeneration: expectedGeneration
                )
            )
            switch response {
            case .save(let result):
                return result
            case .committedMutation(let outcome):
                throw ProjectAccessError.committedMutation(outcome)
            case .failure(let error):
                throw error
            default:
                throw ProjectAccessError.saveUnavailable
            }
        }
    }

    public func finish() async {
        await sequencer.finish { [self] in
            transport = nil
        }
    }
}
