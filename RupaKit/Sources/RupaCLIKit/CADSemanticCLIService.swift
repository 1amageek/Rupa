import Foundation
import RupaAgentProtocol
import RupaCore

public extension CLIService {
    private enum SemanticResponseKind: Sendable {
        case capability
        case program

        var label: String {
            switch self {
            case .capability:
                "capability invocation"
            case .program:
                "semantic program"
            }
        }
    }

    /// Sends one direct semantic request with the authority captured at open.
    func invokeCapability(
        target: CLIDocumentTarget,
        request: AgentSemanticDirectRequest,
        dryRun: Bool = false
    ) async throws -> AgentSemanticExecutionResult {
        try await CLIProjectAccessRunner.withSession(target: target) { session in
            let outerRequest = AgentSemanticDirectExecutionRequest(
                sessionID: session.sessionID,
                authority: session.initialAuthority,
                dryRun: dryRun,
                request: request
            )
            let response = try await session.send(.invokeCapability(outerRequest))
            return try Self.semanticResult(from: response, expected: .capability)
        }
    }

    /// Sends one structured semantic program with the authority captured at open.
    func executeProgram(
        target: CLIDocumentTarget,
        program: AgentSemanticProgramRequest,
        dryRun: Bool = false
    ) async throws -> AgentSemanticExecutionResult {
        try await CLIProjectAccessRunner.withSession(target: target) { session in
            let outerRequest = AgentSemanticProgramExecutionRequest(
                sessionID: session.sessionID,
                authority: session.initialAuthority,
                dryRun: dryRun,
                program: program
            )
            let response = try await session.send(.executeProgram(outerRequest))
            return try Self.semanticResult(from: response, expected: .program)
        }
    }

    private static func semanticResult(
        from response: AgentResponse,
        expected: SemanticResponseKind
    ) throws -> AgentSemanticExecutionResult {
        switch (expected, response) {
        case (.capability, .capabilityExecution(let result)),
             (.program, .programExecution(let result)):
            return result
        case (_, .failure(let error)):
            throw error
        case (_, .committedMutation(let outcome)):
            throw CLICommittedMutationError(outcome: outcome)
        default:
            throw EditorError(
                code: .commandFailed,
                message: "The Agent returned an unexpected response for \(expected.label)."
            )
        }
    }
}

public extension CLIOutput {
    static func write(
        response: AgentSemanticExecutionResult,
        asJSON: Bool
    ) throws {
        let fallback: String = switch response {
        case .success:
            "CAD operation completed."
        case .prepublicationFailure:
            "CAD operation failed before publication."
        case .committedFailure:
            "CAD operation committed with a reported failure."
        }
        try write(response, fallback: fallback, asJSON: asJSON)
    }
}
