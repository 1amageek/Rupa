import Foundation
import RupaAgentProtocol
import RupaCore
import RupaCoreTypes
import RupaMCP

struct CLIRupaMCPAccess: RupaMCPAccess {
    func status() async throws -> AgentStatus {
        let response = try await CLIService().agentStatus()
        return AgentStatus(running: response.running, sessionCount: response.sessionCount)
    }

    func sessions() async throws -> [WorkspaceSessionSummary] {
        try await CLIService().sessions().sessions
    }

    func capabilities() async throws -> [AgentCapabilityDescriptor] {
        try await CLIService().capabilityDescriptors()
    }

    func listViewports(
        target: RupaMCPProjectTarget
    ) async throws -> [AgentViewportState] {
        let response = try await CLIService().send(target: cliTarget(target)) { sessionID in
            .listViewports(sessionID: sessionID)
        }
        guard case .viewportList(let states) = response else {
            throw EditorError(
                code: .commandInvalid,
                message: "Viewport list request returned an unexpected response."
            )
        }
        return states
    }

    func viewportState(
        target: RupaMCPProjectTarget,
        viewportID: UUID
    ) async throws -> AgentViewportState {
        let response = try await CLIService().send(target: cliTarget(target)) { sessionID in
            .viewportState(sessionID: sessionID, viewportID: viewportID)
        }
        guard case .viewportState(let state) = response else {
            throw EditorError(
                code: .commandInvalid,
                message: "Viewport state request returned an unexpected response."
            )
        }
        return state
    }

    func executeViewport(
        target: RupaMCPProjectTarget,
        viewportID: UUID,
        expectedViewportRevision: UInt64?,
        operation: AgentViewportOperation
    ) async throws -> AgentViewportState {
        let response = try await CLIService().send(target: cliTarget(target)) { sessionID in
            .executeViewport(
                sessionID: sessionID,
                viewportID: viewportID,
                expectedViewportRevision: expectedViewportRevision,
                operation: operation
            )
        }
        guard case .viewportExecution(let state) = response else {
            throw EditorError(
                code: .commandInvalid,
                message: "Viewport execution request returned an unexpected response."
            )
        }
        return state
    }

    func invokeCapability(
        target: RupaMCPProjectTarget,
        request: AgentSemanticDirectRequest,
        dryRun: Bool
    ) async throws -> AgentSemanticExecutionResult {
        try await CLIService().invokeCapability(
            target: cliTarget(target),
            request: request,
            dryRun: dryRun
        )
    }

    func executeProgram(
        target: RupaMCPProjectTarget,
        program: AgentSemanticProgramRequest,
        dryRun: Bool
    ) async throws -> AgentSemanticExecutionResult {
        try await CLIService().executeProgram(
            target: cliTarget(target),
            program: program,
            dryRun: dryRun
        )
    }

    func save(
        target: RupaMCPProjectTarget,
        expectedGeneration: DocumentGeneration?
    ) async throws -> SaveResult {
        let response = try await CLIService().saveDocument(
            target: cliTarget(target),
            expectedGeneration: expectedGeneration
        )
        return SaveResult(
            message: response.message,
            path: response.path,
            generation: DocumentGeneration(response.generation),
            dirty: response.dirty,
            diagnostics: response.diagnostics
        )
    }

    private func cliTarget(_ target: RupaMCPProjectTarget) -> CLIDocumentTarget {
        switch target {
        case .project(let url):
            CLIDocumentTarget(fileURL: url)
        case .session(let id):
            CLIDocumentTarget(sessionID: id)
        }
    }
}
