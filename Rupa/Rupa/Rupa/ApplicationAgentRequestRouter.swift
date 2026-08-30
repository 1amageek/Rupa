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

    func handle(_ request: AgentRequest) async -> AgentResponse {
        guard case let .save(sessionID, expectedGeneration) = request else {
            return await projectHandler.handle(request)
        }
        do {
            switch try await lifecycle.save(
                sessionID: sessionID,
                expectedGeneration: expectedGeneration
            ) {
            case .saved(let result):
                return .save(result)
            case .committed(let outcome):
                return .committedMutation(outcome)
            }
        } catch {
            return .failure(errorMapper.editorError(for: error))
        }
    }
}
