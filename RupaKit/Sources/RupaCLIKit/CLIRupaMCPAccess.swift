import Foundation
import RupaAgentProtocol
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
