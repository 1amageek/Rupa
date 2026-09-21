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

    static func semanticResponse(
        from handled: AgentHandledResponse,
        for envelope: AgentRequestEnvelope
    ) throws -> AgentResponse {
        guard case let .planned(response, reservation) = handled else {
            throw AgentResponseEncodingError.invalidPlan(
                "A semantic benchmark request requires a planned response."
            )
        }
        guard reservation.plan.requestID == envelope.id,
              reservation.plan.method == envelope.method else {
            throw AgentResponseEncodingError.invalidPlan(
                "The semantic response reservation does not match the benchmark request."
            )
        }
        let codec = AgentMessageCodec()
        let encoded = try codec.encode(response, consuming: reservation)
        return try codec.decodeResponse(
            from: encoded,
            expectedID: envelope.id,
            expectedMethod: envelope.method
        )
    }
}
