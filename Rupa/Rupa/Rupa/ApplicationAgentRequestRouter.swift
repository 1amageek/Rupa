import RupaAgentProtocol
import RupaAgentRuntime

/// Routes application-owned lifecycle requests without duplicating semantic
/// command dispatch or project authority.
@MainActor
final class ApplicationAgentRequestRouter: AgentRequestHandling {
    private let projectHandler: any AgentRequestHandling
    private let lifecycle: any ApplicationAgentProjectLifecycle
    private let errorMapper: ProjectAgentErrorMapper

    init(
        projectHandler: any AgentRequestHandling,
        lifecycle: any ApplicationAgentProjectLifecycle,
        errorMapper: ProjectAgentErrorMapper = ProjectAgentErrorMapper()
    ) {
        self.projectHandler = projectHandler
        self.lifecycle = lifecycle
        self.errorMapper = errorMapper
    }

    func handle(_ envelope: AgentRequestEnvelope) async -> AgentHandledResponse {
        guard case let .save(sessionID, expectedGeneration) = envelope.params else {
            return await projectHandler.handle(envelope)
        }
        do {
            switch try await lifecycle.save(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration
            ) {
            case .saved(let result):
                return .ordinary(.save(result))
            case .committed(let outcome):
                return .ordinary(.committedMutation(outcome))
            }
        } catch {
            return .ordinary(.failure(errorMapper.editorError(for: error)))
        }
    }
}
