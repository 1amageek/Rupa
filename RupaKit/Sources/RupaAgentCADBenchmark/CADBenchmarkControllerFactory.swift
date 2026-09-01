import RupaAgentProtocol
import RupaAgentRuntime
import RupaCADDomain
import RupaDomainFoundation

/// Builds the benchmark controller with the production CAD semantic registry.
///
/// The benchmark must use the same registry and compiler composition as the
/// application. This helper is intentionally internal and owns no project or
/// persistence state.
@MainActor
enum CADBenchmarkControllerFactory {
    static func make(name: String) throws -> ProjectAgentCommandController {
        let registry = try RupaCADDomain.registry()
        return ProjectAgentCommandController(
            name: name,
            semanticProgramCompiler: DefaultSemanticProgramCompiler(registry: registry)
        )
    }

    static func envelope(
        request: AgentRequest,
        id: String
    ) -> AgentRequestEnvelope {
        AgentRequestEnvelope(id: id, params: request)
    }

    static func ordinaryResponse(
        from handled: AgentHandledResponse
    ) throws -> AgentResponse {
        guard case let .ordinary(response) = handled else {
            throw CADBenchmarkControllerError.unexpectedPlannedResponse
        }
        return response
    }
}

enum CADBenchmarkControllerError: Error, Equatable, Sendable {
    case unexpectedPlannedResponse
}
