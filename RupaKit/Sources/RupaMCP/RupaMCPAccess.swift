import RupaAgentProtocol
import RupaCoreTypes

public protocol RupaMCPAccess: Sendable {
    func status() async throws -> AgentStatus
    func sessions() async throws -> [WorkspaceSessionSummary]
    func capabilities() async throws -> [AgentCapabilityDescriptor]
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
