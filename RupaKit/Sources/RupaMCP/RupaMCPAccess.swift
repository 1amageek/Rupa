import Foundation
import RupaAgentProtocol
import RupaCoreTypes

public protocol RupaMCPAccess: Sendable {
    func status() async throws -> AgentStatus
    func sessions() async throws -> [WorkspaceSessionSummary]
    func capabilities() async throws -> [AgentCapabilityDescriptor]
    func listViewports(
        target: RupaMCPProjectTarget
    ) async throws -> [AgentViewportState]
    func viewportState(
        target: RupaMCPProjectTarget,
        viewportID: UUID
    ) async throws -> AgentViewportState
    func executeViewport(
        target: RupaMCPProjectTarget,
        viewportID: UUID,
        expectedViewportRevision: UInt64?,
        operation: AgentViewportOperation
    ) async throws -> AgentViewportState
    func invokeCapability(
        target: RupaMCPProjectTarget,
        request: AgentSemanticDirectRequest,
        dryRun: Bool
    ) async throws -> AgentSemanticExecutionResult
    func executeProgram(
        target: RupaMCPProjectTarget,
        program: AgentSemanticProgramRequest,
        dryRun: Bool
    ) async throws -> AgentSemanticExecutionResult
    func save(
        target: RupaMCPProjectTarget,
        expectedGeneration: DocumentGeneration?
    ) async throws -> SaveResult
}
