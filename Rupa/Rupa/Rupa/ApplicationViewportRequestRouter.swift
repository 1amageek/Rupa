import RupaAgentProtocol
import RupaAgentRuntime

/// Enters UI isolation only for explicit, transient viewport operations.
nonisolated final class ApplicationViewportRequestRouter: AgentRequestHandling {
    private let downstream: any AgentRequestHandling
    private let viewports: ApplicationViewportRegistry
    private let errorMapper = ProjectAgentErrorMapper()

    init(downstream: any AgentRequestHandling, viewports: ApplicationViewportRegistry) {
        self.downstream = downstream
        self.viewports = viewports
    }

    func handle(_ envelope: AgentRequestEnvelope) async -> AgentHandledResponse {
        do {
            switch envelope.params {
            case .listViewports(let sessionID):
                return .ordinary(.viewportList(try await viewports.list(sessionID: sessionID)))
            case .viewportState(let sessionID, let viewportID):
                return .ordinary(.viewportState(try await viewports.state(
                    sessionID: sessionID, viewportID: viewportID
                )))
            case .executeViewport(let sessionID, let viewportID, let revision, let operation):
                return .ordinary(.viewportExecution(try await viewports.execute(
                    sessionID: sessionID, viewportID: viewportID,
                    expectedRevision: revision, operation: operation
                )))
            default:
                return await downstream.handle(envelope)
            }
        } catch {
            return .ordinary(.failure(errorMapper.editorError(for: error)))
        }
    }
}
